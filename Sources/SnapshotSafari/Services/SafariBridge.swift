import Foundation
import SwiftUI
import OSAKit
import os.log

// MARK: - Errors

enum SafariBridgeError: LocalizedError {
    case safariNotRunning
    case permissionDenied
    case scriptError(String)
    case invalidOutput
    case noTabsFound
    case appleEventTimeout

    var errorDescription: String? {
        switch self {
        case .safariNotRunning:
            return "Safari is not running. Please open Safari first."
        case .permissionDenied:
            return "Snapshot Safari doesn't have permission to control Safari. Grant Automation access in System Settings → Privacy & Security → Automation."
        case .scriptError(let detail):
            return "Script error: \(detail)"
        case .invalidOutput:
            return "Could not parse Safari tab data."
        case .noTabsFound:
            return "No open tabs found in Safari."
        case .appleEventTimeout:
            return "Safari didn't respond in time. It may be busy or unresponsive — try again."
        }
    }
}

// MARK: - Tab Data

struct SafariTab: Codable, Identifiable, Equatable {
    /// Safari can return `null` for tabs that have no real URL (e.g. the
    /// start page, internal pages). We model this as an optional String
    /// so JSONDecoder doesn't throw on the entire response.
    let url: String?
    let title: String
    let windowIndex: Int
    let index: Int

    var id: String { "\(windowIndex)-\(index)-\(url ?? "null")" }

    static func == (lhs: SafariTab, rhs: SafariTab) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - JXA Script Templates
//
// Templates are kept as static constants so they can be unit-tested
// without launching osascript. The runtime executes them via
// `OSAScript` (in-process), which makes THIS app's bundle ID the
// sender of the AppleEvents — so the TCC grant lands on
// `com.ernest.snapshot-safari` in System Settings → Privacy & Security
// → Automation, not on `com.apple.osascript`.

enum SafariScripts {

    /// Builds the JXA script that reads every open Safari tab.
    /// Pure function of no inputs. Output is `JSON.stringify([{url, title, windowIndex, index}, ...])`.
    static let readAllTabs = """
    function run() {
        var safari = Application('Safari');
        safari.includeStandardAdditions = true;
        var windows = safari.windows();
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

    /// Builds the JXA script that opens the given tabs in a new Safari window.
    /// `tabsJSON` must be a pre-escaped JSON array string.
    static func restoreInNewWindow(tabsJSON: String) -> String {
        return """
        function run() {
            var safari = Application('Safari');
            safari.includeStandardAdditions = true;
            var tabs = JSON.parse('\(tabsJSON)');
            var newWindow = safari.Window().make();
            for (var i = 0; i < tabs.length; i++) {
                var tab = safari.Tab({url: tabs[i].url});
                newWindow.tabs.push(tab);
            }
            newWindow.visible = true;
            return "Restored " + tabs.length + " tabs in new window.";
        }
        """
    }

    /// Builds the JXA script that appends the given tabs to Safari's front window.
    /// Creates a new window if none is open. `tabsJSON` is a pre-escaped JSON array string.
    static func restoreInCurrentWindow(tabsJSON: String) -> String {
        return """
        function run() {
            var safari = Application('Safari');
            safari.includeStandardAdditions = true;
            var tabs = JSON.parse('\(tabsJSON)');
            if (safari.windows.length === 0) {
                var newWindow = safari.Window().make();
                for (var i = 0; i < tabs.length; i++) {
                    var tab = safari.Tab({url: tabs[i].url});
                    newWindow.tabs.push(tab);
                }
                return "Restored " + tabs.length + " tabs in new window (none was open).";
            }
            var frontWindow = safari.windows[0];
            for (var i = 0; i < tabs.length; i++) {
                var tab = safari.Tab({url: tabs[i].url});
                frontWindow.tabs.push(tab);
            }
            return "Restored " + tabs.length + " tabs in current window.";
        }
        """
    }
}

// MARK: - Bridge

final class SafariBridge {

    private let logger = Logger(subsystem: "com.ernest.snapshot-safari", category: "SafariBridge")

    /// Check if Safari is running
    var isSafariRunning: Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari")
        return !apps.isEmpty
    }

    // MARK: - Read Tabs

    /// Returns all open tabs from all Safari windows.
    /// AppleEvents are sent from THIS process (bundle id `com.ernest.snapshot-safari`),
    /// so the user grants TCC permission to Snapshot Safari directly.
    func readAllTabs() async throws -> [SafariTab] {
        guard isSafariRunning else {
            throw SafariBridgeError.safariNotRunning
        }

        let result: String
        do {
            result = try await runScript(SafariScripts.readAllTabs)
        } catch let error as OSAScriptError where Self.isPermissionError(error) {
            throw SafariBridgeError.permissionDenied
        }

        guard let data = result.data(using: .utf8) else {
            throw SafariBridgeError.invalidOutput
        }
        do {
            return try JSONDecoder().decode([SafariTab].self, from: data)
        } catch {
            logger.error("Failed to decode Safari tab JSON: \(error.localizedDescription)")
            throw SafariBridgeError.invalidOutput
        }
    }

    // MARK: - Restore Tabs

    enum RestoreMode: String, CaseIterable {
        case newWindow = "New Safari Window"
        case currentWindow = "Current Window (append)"
    }

    /// Opens tabs in Safari using the selected mode.
    /// Tabs with `nil` URLs are silently dropped — Safari can't open
    /// a tab without a URL, and these represent internal pages (start
    /// page, etc.) that have no address to restore.
    func restoreTabs(_ tabs: [SafariTab], mode: RestoreMode) async throws {
        guard isSafariRunning else {
            throw SafariBridgeError.safariNotRunning
        }

        // Filter out tabs with nil URLs (Safari internal pages)
        // and default to "about:blank" for safety — Safari handles this.
        let safeTabs = tabs.compactMap { tab -> SafariTab? in
            guard tab.url != nil else {
                logger.debug("Skipping tab with nil URL: \(tab.title)")
                return nil
            }
            return tab
        }

        guard !safeTabs.isEmpty else {
            throw SafariBridgeError.noTabsFound
        }

        let jsonData = try JSONEncoder().encode(safeTabs)
        let jsonString = String(data: jsonData, encoding: .utf8)?
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'") ?? "[]"

        let script: String
        switch mode {
        case .newWindow:
            script = SafariScripts.restoreInNewWindow(tabsJSON: jsonString)
        case .currentWindow:
            script = SafariScripts.restoreInCurrentWindow(tabsJSON: jsonString)
        }

        do {
            _ = try await runScript(script)
        } catch let error as OSAScriptError where Self.isPermissionError(error) {
            throw SafariBridgeError.permissionDenied
        }
    }

    /// Timeout for AppleEvent delivery to Safari. If Safari is hung
    /// or unresponsive, the main-thread `executeAndReturnError` would
    /// otherwise beachball the UI indefinitely.
    private static let appleEventTimeoutSeconds: TimeInterval = 15

    // MARK: - In-process Script Execution

    /// Executes a JXA script in-process using `OSAScript`. Returns the script's
    /// string result. Throws `OSAScriptError` on script failure,
    /// `SafariBridgeError.appleEventTimeout` if Safari doesn't respond in time.
    ///
    /// Running in-process (vs spawning `/usr/bin/osascript`) means the AppleEvent
    /// sender is OUR bundle id — so when the user is prompted for permission,
    /// macOS shows "Snapshot Safari wants to control Safari" and the TCC grant
    /// is recorded against `com.ernest.snapshot-safari`, putting our app in
    /// System Settings → Privacy & Security → Automation.
    ///
    /// Executes on the main actor because AppleEvents require a run loop
    /// to process replies. Wrapped in a `withTimeout` so the caller gets
    /// an error (rather than hanging indefinitely) if Safari is hung.
    ///
    /// NOTE: `MainActor.run` runs the closure synchronously on the main
    /// thread. When Safari is hung, the main thread remains blocked inside
    /// `executeAndReturnError` for the OS-level AppleEvent timeout (~120 s).
    /// The `withTimeout` gives the calling task an early error, but the UI
    /// may still beachball until the AppleEvent layer gives up.
    private func runScript(_ source: String) async throws -> String {
        // NSAppleEventDescriptor / NSDictionary / OSALanguage are not Sendable,
        // so the `withTimeout` closure only captures Sendable values (String).
        // Everything non-Sendable is created inside `MainActor.run`.
        let result: (stringValue: String?, errorCode: Int, errorMessage: String)
        do {
            result = try await withTimeout(seconds: Self.appleEventTimeoutSeconds) {
                await MainActor.run { () -> (stringValue: String?, errorCode: Int, errorMessage: String) in
                    guard let language = OSALanguage(forName: "JavaScript") else {
                        return (nil, -1, "JavaScript OSA language unavailable")
                    }
                    let script = OSAScript(source: source, language: language)
                    var error: NSDictionary?
                    let outcome = script.executeAndReturnError(&error)

                    if let error {
                        let message = Self.describeOSAError(error)
                        let code = (error[OSAScriptErrorNumberKey] as? Int) ?? 0
                        return (nil, code, message)
                    }

                    return (outcome?.stringValue, 0, "")
                }
            }
        } catch is TimeoutError {
            logger.warning("AppleEvent timed out after \(Self.appleEventTimeoutSeconds)s — Safari may be hung")
            throw SafariBridgeError.appleEventTimeout
        }

        if result.errorCode != 0 {
            throw OSAScriptError(
                info: [
                    OSAScriptErrorNumberKey: result.errorCode,
                    OSAScriptErrorMessageKey: result.errorMessage
                ],
                message: result.errorMessage
            )
        }

        // Some scripts (notably `restoreTabs`) don't return a value but
        // still succeed. Treat nil-string as success.
        return result.stringValue ?? ""
    }

    /// Wraps a non-descript OSA error info dictionary so call sites can pattern-match.
    private static func describeOSAError(_ info: NSDictionary) -> String {
        if let msg = info[OSAScriptErrorMessageKey] as? String, !msg.isEmpty {
            return msg
        }
        if let msg = info["ErrorMessage"] as? String, !msg.isEmpty {
            return msg
        }
        if let num = info[OSAScriptErrorNumberKey] as? Int {
            return "OSA error \(num)"
        }
        return "OSA script failed"
    }

    /// True if the OSA error indicates TCC denied an AppleEvent.
    /// errAEEventNotHandled = -1708 (recipient refused)
    /// errOSACannotLaunch = -1750
    /// errAEEventFailed = -1709
    static func isPermissionError(_ error: OSAScriptError) -> Bool {
        let code = error.code
        return code == -1708 || code == -1709 || code == -1750 ||
               code == errAEEventNotHandled || code == errAEEventFailed
    }
}

/// Concrete error type wrapping the OSA error info dictionary.
/// Exposes the four-char error code as `code` so callers can match.
/// Marked `@unchecked Sendable` because `NSDictionary` is a reference type
/// that does not conform to `Sendable`, but we treat the dictionary as
/// immutable after construction (OSA only writes to it once during a failed
/// execution) and we only read it from the throwing site.
struct OSAScriptError: Error, @unchecked Sendable {
    let info: NSDictionary
    let message: String

    /// Best-effort integer code (may be the AppleEvent Manager's negative number
    /// or an OSA error number, depending on which key the dictionary contains).
    var code: Int {
        if let n = info[OSAScriptErrorNumberKey] as? Int { return n }
        if let n = info["errAEEventNumber"] as? Int { return n }
        return 0
    }
}

// MARK: - Timeout Helper

/// Thrown when an async operation exceeds its deadline.
private struct TimeoutError: Error {}

/// Races `operation` against a timeout. If `operation` completes first,
/// its result is returned. If the timeout fires first, `TimeoutError`
/// is thrown and the operation task is cancelled.
///
/// Uses `TaskGroup` so the timeout runs on a separate cooperative
/// task — it doesn't need the main thread, so it fires even if
/// `operation` is blocking the main actor.
private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        guard let result = try await group.next() else {
            // Both tasks completed without producing a value — should never
            // happen given our two tasks, but treat as timeout defensively.
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}