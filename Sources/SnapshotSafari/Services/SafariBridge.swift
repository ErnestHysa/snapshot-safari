import Foundation
import SwiftUI

// MARK: - Errors

enum SafariBridgeError: LocalizedError {
    case safariNotRunning
    case permissionDenied
    case scriptError(String)
    case invalidOutput
    case noTabsFound

    var errorDescription: String? {
        switch self {
        case .safariNotRunning:
            return "Safari is not running. Please open Safari first."
        case .permissionDenied:
            return "Permission denied. Grant Automation access to Safari in System Settings > Privacy & Security > Automation."
        case .scriptError(let detail):
            return "Script error: \(detail)"
        case .invalidOutput:
            return "Could not parse Safari tab data."
        case .noTabsFound:
            return "No open tabs found in Safari."
        }
    }
}

// MARK: - Tab Data

struct SafariTab: Codable, Identifiable, Equatable {
    let url: String
    let title: String
    let windowIndex: Int
    let index: Int

    var id: String { "\(windowIndex)-\(index)-\(url)" }

    static func == (lhs: SafariTab, rhs: SafariTab) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Bridge

final class SafariBridge {

    /// Check if Safari is running
    var isSafariRunning: Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari")
        return !apps.isEmpty
    }

    // MARK: - Read Tabs

    /// Returns all open tabs from all Safari windows
    func readAllTabs() async throws -> [SafariTab] {
        guard isSafariRunning else {
            throw SafariBridgeError.safariNotRunning
        }

        let jxaScript = """
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

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let result = try Self.runJXA(jxaScript)
                    guard let data = result.data(using: .utf8) else {
                        throw SafariBridgeError.invalidOutput
                    }
                    let decoder = JSONDecoder()
                    let tabs = try decoder.decode([SafariTab].self, from: data)
                    continuation.resume(returning: tabs)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Restore Tabs

    enum RestoreMode: String, CaseIterable {
        case newWindow = "New Safari Window"
        case currentWindow = "Current Window (append)"
    }

    /// Opens tabs in Safari
    func restoreTabs(_ tabs: [SafariTab], mode: RestoreMode) async throws {
        guard isSafariRunning else {
            throw SafariBridgeError.safariNotRunning
        }

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(tabs)
        let jsonString = String(data: jsonData, encoding: .utf8)!
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let jxaScript: String
        switch mode {
        case .newWindow:
            jxaScript = """
            function run() {
                var safari = Application('Safari');
                safari.includeStandardAdditions = true;
                var tabs = JSON.parse('\(jsonString)');
                var newWindow = safari.Window().make();
                for (var i = 0; i < tabs.length; i++) {
                    var tab = safari.Tab({url: tabs[i].url});
                    newWindow.tabs.push(tab);
                }
                newWindow.visible = true;
                return "Restored " + tabs.length + " tabs in new window.";
            }
            """
        case .currentWindow:
            jxaScript = """
            function run() {
                var safari = Application('Safari');
                safari.includeStandardAdditions = true;
                var tabs = JSON.parse('\(jsonString)');
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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                do {
                    let _ = try Self.runJXA(jxaScript)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private static func runJXA(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw SafariBridgeError.scriptError(errorOutput.isEmpty ? "Exit code \(process.terminationStatus)" : errorOutput)
        }

        return output
    }
}
