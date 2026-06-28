import Foundation
import AppKit
import OSAKit
import os.log

// MARK: - Errors

enum BrowserBridgeError: LocalizedError {
    case browserNotRunning(Browser)
    case permissionDenied(Browser)
    case scriptError(String)
    case invalidOutput
    case noTabsFound
    case appleEventTimeout
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .browserNotRunning(let browser):
            return "\(browser.displayName) is not running. Please open \(browser.shortName) first."
        case .permissionDenied(let browser):
            return "Snapshot Safari doesn't have permission to control \(browser.displayName). Grant Automation access in System Settings → Privacy & Security → Automation."
        case .scriptError(let detail):
            return "Script error: \(detail)"
        case .invalidOutput:
            return "Could not parse browser tab data."
        case .noTabsFound:
            return "No open tabs found."
        case .appleEventTimeout:
            return "The browser didn't respond in time. It may be busy or unresponsive — try again."
        case .unsupportedOperation(let detail):
            return detail
        }
    }
}

// MARK: - Tab Data

struct BrowserTab: Codable, Identifiable, Equatable {
    let url: String?
    let title: String
    let windowIndex: Int
    let index: Int
    let browserId: String

    var id: String { "\(browserId)-\(windowIndex)-\(index)-\(url ?? "null")" }

    static func == (lhs: BrowserTab, rhs: BrowserTab) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Restore Mode

enum BrowserRestoreMode: String, CaseIterable {
    case newWindow = "New Window"
    case currentWindow = "Current Window (append)"
}

// MARK: - Bridge Protocol

protocol BrowserBridge {
    var browser: Browser { get }
    func readAllTabs() async throws -> [BrowserTab]
    func restoreTabs(_ tabs: [BrowserTab], mode: BrowserRestoreMode) async throws -> Int
}

// MARK: - JXA Script Execution

/// Shared JXA execution engine used by all bridge implementations.
/// Handles in-process script execution, timeout, and TCC permission retry logic.
final class JXAScriptRunner {
    private let logger = Logger(subsystem: "com.ernest.snapshot-safari", category: "JXARunner")
    private static let appleEventTimeoutSeconds: TimeInterval = 30

    /// Execute a JXA script in-process. Returns the script's string result.
    func execute(_ source: String) async throws -> String {
        do {
            return try await execute(on: .global(), source: source)
        } catch let error as OSAScriptError where Self.isPermissionError(error) {
            logger.debug("Permission error on background queue, retrying on main thread")
            return try await execute(on: .main, source: source)
        }
    }

    private func execute(on queue: DispatchQueue, source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            queue.async {
                guard let language = OSALanguage(forName: "JavaScript") else {
                    lock.lock()
                    if !hasResumed {
                        hasResumed = true
                        lock.unlock()
                        continuation.resume(
                            throwing: BrowserBridgeError.scriptError("JavaScript OSA language unavailable")
                        )
                    } else {
                        lock.unlock()
                    }
                    return
                }

                let script = OSAScript(source: source, language: language)
                var error: NSDictionary?
                let outcome = script.executeAndReturnError(&error)

                lock.lock()
                guard !hasResumed else {
                    lock.unlock()
                    return
                }
                hasResumed = true
                lock.unlock()

                if let error {
                    let message = Self.describeOSAError(error)
                    let code = (error[OSAScriptErrorNumberKey] as? Int) ?? 0
                    continuation.resume(throwing: OSAScriptError(
                        info: [OSAScriptErrorNumberKey: code, OSAScriptErrorMessageKey: message],
                        message: message
                    ))
                } else {
                    continuation.resume(returning: outcome?.stringValue ?? "")
                }
            }

            let logger = self.logger
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.appleEventTimeoutSeconds) {
                lock.lock()
                guard !hasResumed else {
                    lock.unlock()
                    return
                }
                hasResumed = true
                lock.unlock()
                logger.warning("AppleEvent timed out after \(Self.appleEventTimeoutSeconds)s")
                continuation.resume(throwing: BrowserBridgeError.appleEventTimeout)
            }
        }
    }

    static func isPermissionError(_ error: OSAScriptError) -> Bool {
        let code = error.code
        return code == -1708 || code == -1709 || code == -1750 ||
               code == errAEEventNotHandled || code == errAEEventFailed
    }

    private static func describeOSAError(_ info: NSDictionary) -> String {
        if let msg = info[OSAScriptErrorMessageKey] as? String, !msg.isEmpty { return msg }
        if let msg = info["ErrorMessage"] as? String, !msg.isEmpty { return msg }
        if let num = info[OSAScriptErrorNumberKey] as? Int { return "OSA error \(num)" }
        return "OSA script failed"
    }
}

// MARK: - WebKit Bridge (Safari, Orion)

final class WebKitBridge: BrowserBridge {
    let browser: Browser
    private let runner = JXAScriptRunner()
    private let logger = Logger(subsystem: "com.ernest.snapshot-safari", category: "WebKitBridge")

    init(browser: Browser) {
        precondition(browser.engine == .webkit, "WebKitBridge only supports WebKit browsers")
        self.browser = browser
    }

    func readAllTabs() async throws -> [BrowserTab] {
        guard browser.isRunning else {
            throw BrowserBridgeError.browserNotRunning(browser)
        }

        let result: String
        do {
            result = try await runner.execute(readAllTabsScript)
        } catch let error as OSAScriptError where JXAScriptRunner.isPermissionError(error) {
            throw BrowserBridgeError.permissionDenied(browser)
        }

        guard let data = result.data(using: .utf8) else {
            throw BrowserBridgeError.invalidOutput
        }
        do {
            let rawTabs = try JSONDecoder().decode([RawJXATab].self, from: data)
            return rawTabs.map { raw in
                BrowserTab(
                    url: raw.url,
                    title: raw.title,
                    windowIndex: raw.windowIndex,
                    index: raw.index,
                    browserId: browser.rawValue
                )
            }
        } catch {
            logger.error("Failed to decode \(self.browser.shortName) tab JSON: \(error.localizedDescription)")
            throw BrowserBridgeError.invalidOutput
        }
    }

    func restoreTabs(_ tabs: [BrowserTab], mode: BrowserRestoreMode) async throws -> Int {
        guard browser.isRunning else {
            throw BrowserBridgeError.browserNotRunning(browser)
        }

        let safeTabs = tabs.compactMap { tab -> BrowserTab? in
            guard let url = tab.url, !url.isEmpty, url != "about:blank" else { return nil }
            return tab
        }

        guard !safeTabs.isEmpty else {
            throw BrowserBridgeError.noTabsFound
        }

        let jsonData = try JSONEncoder().encode(safeTabs)
        let jsonString = String(data: jsonData, encoding: .utf8)?
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'") ?? "[]"

        let script: String
        switch mode {
        case .newWindow:
            script = restoreInNewWindowScript(tabsJSON: jsonString)
        case .currentWindow:
            script = restoreInCurrentWindowScript(tabsJSON: jsonString)
        }

        do {
            _ = try await runner.execute(script)
            return safeTabs.count
        } catch let error as OSAScriptError where JXAScriptRunner.isPermissionError(error) {
            throw BrowserBridgeError.permissionDenied(browser)
        }
    }

    // MARK: - JXA Scripts

    private var readAllTabsScript: String {
        """
        function run() {
            var browser = Application('\(browser.jxaAppName)');
            browser.includeStandardAdditions = true;
            var windows = browser.windows();
            var tabs = [];

            for (var w = 0; w < windows.length; w++) {
                var win = windows[w];
                var winTabs = win.tabs;
                for (var t = 0; t < winTabs.length; t++) {
                    tabs.push({
                        url: winTabs[t].url(),
                        title: winTabs[t].name(),
                        windowIndex: w,
                        index: t
                    });
                }
            }

            return JSON.stringify(tabs);
        }
        """
    }

    private func restoreInNewWindowScript(tabsJSON: String) -> String {
        """
        function run() {
            var browser = Application('\(browser.jxaAppName)');
            browser.includeStandardAdditions = true;
            browser.activate();

            var tabs = JSON.parse('\(tabsJSON)');

            var doc = browser.Document({url: tabs[0].url});
            browser.documents.push(doc);

            if (tabs.length > 1) {
                var newWindow = browser.windows[0];
                for (var i = 1; i < tabs.length; i++) {
                    newWindow.tabs.push(
                        browser.Tab({url: tabs[i].url})
                    );
                }
            }

            return "Restored " + tabs.length + " tabs.";
        }
        """
    }

    private func restoreInCurrentWindowScript(tabsJSON: String) -> String {
        """
        function run() {
            var browser = Application('\(browser.jxaAppName)');
            browser.includeStandardAdditions = true;
            var tabs = JSON.parse('\(tabsJSON)');

            if (browser.windows.length === 0) {
                browser.openLocation(tabs[0].url);
                var newWindow = browser.windows[0];
                for (var i = 1; i < tabs.length; i++) {
                    newWindow.tabs.push(
                        browser.Tab({url: tabs[i].url})
                    );
                }
                return "Restored " + tabs.length + " tabs.";
            }

            var frontWindow = browser.windows[0];
            for (var i = 0; i < tabs.length; i++) {
                frontWindow.tabs.push(
                    browser.Tab({url: tabs[i].url})
                );
            }
            return "Restored " + tabs.length + " tabs.";
        }
        """
    }
}

// MARK: - Chromium Bridge (Chrome, Brave, Edge, Opera, Vivaldi)

final class ChromiumBridge: BrowserBridge {
    let browser: Browser
    private let runner = JXAScriptRunner()
    private let logger = Logger(subsystem: "com.ernest.snapshot-safari", category: "ChromiumBridge")

    init(browser: Browser) {
        precondition(browser.engine == .chromium, "ChromiumBridge only supports Chromium browsers")
        self.browser = browser
    }

    func readAllTabs() async throws -> [BrowserTab] {
        guard browser.isRunning else {
            throw BrowserBridgeError.browserNotRunning(browser)
        }

        let result: String
        do {
            result = try await runner.execute(readAllTabsScript)
        } catch let error as OSAScriptError where JXAScriptRunner.isPermissionError(error) {
            throw BrowserBridgeError.permissionDenied(browser)
        }

        guard let data = result.data(using: .utf8) else {
            throw BrowserBridgeError.invalidOutput
        }
        do {
            let rawTabs = try JSONDecoder().decode([RawJXATab].self, from: data)
            return rawTabs.map { raw in
                BrowserTab(
                    url: raw.url,
                    title: raw.title,
                    windowIndex: raw.windowIndex,
                    index: raw.index,
                    browserId: browser.rawValue
                )
            }
        } catch {
            logger.error("Failed to decode \(self.browser.shortName) tab JSON: \(error.localizedDescription)")
            throw BrowserBridgeError.invalidOutput
        }
    }

    func restoreTabs(_ tabs: [BrowserTab], mode: BrowserRestoreMode) async throws -> Int {
        // Launch browser if not running
        if !browser.isRunning {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.rawValue) {
                let config = NSWorkspace.OpenConfiguration()
                try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                // Brief wait for browser to start
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            guard browser.isRunning else {
                throw BrowserBridgeError.browserNotRunning(browser)
            }
        }

        let safeTabs = tabs.compactMap { tab -> BrowserTab? in
            guard let url = tab.url, !url.isEmpty, url != "about:blank" else { return nil }
            return tab
        }

        guard !safeTabs.isEmpty else {
            throw BrowserBridgeError.noTabsFound
        }

        let jsonData = try JSONEncoder().encode(safeTabs)
        let jsonString = String(data: jsonData, encoding: .utf8)?
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'") ?? "[]"

        let script: String
        switch mode {
        case .newWindow:
            script = restoreInNewWindowScript(tabsJSON: jsonString)
        case .currentWindow:
            script = restoreInCurrentWindowScript(tabsJSON: jsonString)
        }

        do {
            _ = try await runner.execute(script)
            return safeTabs.count
        } catch let error as OSAScriptError where JXAScriptRunner.isPermissionError(error) {
            throw BrowserBridgeError.permissionDenied(browser)
        }
    }

    // MARK: - JXA Scripts (Chromium)

    private var readAllTabsScript: String {
        """
        function run() {
            var browser = Application('\(browser.jxaAppName)');
            browser.includeStandardAdditions = true;
            var windows = browser.windows();
            var tabs = [];

            for (var w = 0; w < windows.length; w++) {
                var win = windows[w];
                var winTabs = win.tabs;
                for (var t = 0; t < winTabs.length; t++) {
                    tabs.push({
                        url: winTabs[t].url(),
                        title: winTabs[t].title(),
                        windowIndex: w,
                        index: t
                    });
                }
            }

            return JSON.stringify(tabs);
        }
        """
    }

    private func restoreInNewWindowScript(tabsJSON: String) -> String {
        """
        function run() {
            var browser = Application('\(browser.jxaAppName)');
            browser.includeStandardAdditions = true;
            browser.activate();

            var tabs = JSON.parse('\(tabsJSON)');

            var newWin = browser.Window().make();
            newWin.activeTab.url = tabs[0].url;

            for (var i = 1; i < tabs.length; i++) {
                var tab = browser.Tab({url: tabs[i].url});
                newWin.tabs.push(tab);
            }

            return "Restored " + tabs.length + " tabs.";
        }
        """
    }

    private func restoreInCurrentWindowScript(tabsJSON: String) -> String {
        """
        function run() {
            var browser = Application('\(browser.jxaAppName)');
            browser.includeStandardAdditions = true;
            var tabs = JSON.parse('\(tabsJSON)');

            if (browser.windows.length === 0) {
                var newWin = browser.Window().make();
                newWin.activeTab.url = tabs[0].url;
                for (var i = 1; i < tabs.length; i++) {
                    var tab = browser.Tab({url: tabs[i].url});
                    newWin.tabs.push(tab);
                }
                return "Restored " + tabs.length + " tabs.";
            }

            var frontWindow = browser.windows[0];
            for (var i = 0; i < tabs.length; i++) {
                var tab = browser.Tab({url: tabs[i].url});
                frontWindow.tabs.push(tab);
            }
            return "Restored " + tabs.length + " tabs.";
        }
        """
    }
}

// MARK: - Unscriptable Bridge (Arc, Firefox)

/// For browsers that lack a scripting dictionary: can only open URLs,
/// not read tabs.
final class UnscriptableBridge: BrowserBridge {
    let browser: Browser

    init(browser: Browser) {
        precondition(browser.engine == .unscriptable, "UnscriptableBridge only supports unscriptable browsers")
        self.browser = browser
    }

    func readAllTabs() async throws -> [BrowserTab] {
        throw BrowserBridgeError.unsupportedOperation(
            "\(browser.displayName) does not support tab reading via AppleEvents. Use Safari, Chrome, Brave, Edge, Opera, Vivaldi, or Orion instead."
        )
    }

    func restoreTabs(_ tabs: [BrowserTab], mode: BrowserRestoreMode) async throws -> Int {
        let safeTabs = tabs.compactMap { tab -> BrowserTab? in
            guard let url = tab.url, !url.isEmpty, url != "about:blank",
                  let _ = URL(string: url) else { return nil }
            return tab
        }

        guard !safeTabs.isEmpty else {
            throw BrowserBridgeError.noTabsFound
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.rawValue) else {
            throw BrowserBridgeError.browserNotRunning(browser)
        }

        var count = 0
        for tab in safeTabs {
            guard let url = URL(string: tab.url!) else { continue }
            let config = NSWorkspace.OpenConfiguration()
            try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
            count += 1
            // Small delay to avoid overwhelming the browser
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        return count
    }
}

// MARK: - Bridge Factory

enum BrowserBridgeFactory {
    static func create(for browser: Browser) -> any BrowserBridge {
        switch browser.engine {
        case .webkit:
            return WebKitBridge(browser: browser)
        case .chromium:
            return ChromiumBridge(browser: browser)
        case .unscriptable:
            return UnscriptableBridge(browser: browser)
        }
    }
}

// MARK: - Raw JXA Tab (internal JSON decode helper)

private struct RawJXATab: Codable {
    let url: String?
    let title: String
    let windowIndex: Int
    let index: Int
}

// MARK: - OSA Script Error

/// Concrete error type wrapping the OSA error info dictionary.
/// Defined here so BrowserBridge can use it; the legacy SafariBridge.swift
/// no longer exists.
struct OSAScriptError: Error, @unchecked Sendable {
    let info: NSDictionary
    let message: String

    var code: Int {
        if let n = info[OSAScriptErrorNumberKey] as? Int { return n }
        if let n = info["errAEEventNumber"] as? Int { return n }
        return 0
    }
}
