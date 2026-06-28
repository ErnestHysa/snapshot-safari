import Foundation
import AppKit
import ApplicationServices
import OSAKit
import os.log

/// Tracks whether Snapshot Safari has been granted Automation access to each
/// supported browser.
///
/// On modern macOS, when an app sends an AppleEvent to another app for the first
/// time, the system automatically prompts the user to grant permission. The
/// result is recorded against THIS bundle id (`com.ernest.snapshot-safari`) in
/// System Settings → Privacy & Security → Automation — NOT against `osascript`.
///
/// Permissions are tracked per-browser because TCC grants are per-target app.
@Observable
final class PermissionsService {
    /// Dictionary of browser bundle ID → permission granted.
    var permissions: [String: Bool] = [:]
    var isChecking: Bool = false

    private let logger = Logger(subsystem: "com.ernest.snapshot-safari", category: "Permissions")

    /// Legacy property for backward compatibility with existing UI.
    var hasAutomationPermission: Bool {
        permissions[Browser.safari.rawValue] ?? false
    }

    // MARK: - Check Individual Browser

    /// Probe a specific browser for Automation permission.
    @MainActor
    func checkPermission(for browser: Browser) async -> Bool {
        guard browser.supportsReadTabs else {
            permissions[browser.rawValue] = false
            return false
        }

        guard browser.isRunning else {
            logger.debug("\(browser.shortName) is not running — treating as not granted")
            permissions[browser.rawValue] = false
            return false
        }

        let script = """
        function run() {
            var browser = Application('\(browser.jxaAppName)');
            return String(browser.windows.length);
        }
        """

        guard let language = OSALanguage(forName: "JavaScript") else {
            logger.error("JavaScript OSA language unavailable")
            permissions[browser.rawValue] = false
            return false
        }

        let result = OSAScript(source: script, language: language)
        var error: NSDictionary?
        let outcome = result.executeAndReturnError(&error)

        if let error {
            let code = (error[OSAScriptErrorNumberKey] as? Int) ?? 0
            logger.debug("\(browser.shortName) probe error code=\(code)")
            permissions[browser.rawValue] = false
        } else if outcome?.stringValue != nil {
            logger.debug("\(browser.shortName) probe succeeded")
            permissions[browser.rawValue] = true
        } else {
            permissions[browser.rawValue] = false
        }

        return permissions[browser.rawValue] ?? false
    }

    // MARK: - Check All

    /// Check permissions for all installed & readable browsers.
    @MainActor
    func checkAllPermissions() async {
        isChecking = true
        defer { isChecking = false }

        let toCheck = Browser.allCases.filter { $0.isInstalled && $0.supportsReadTabs }

        for browser in toCheck {
            _ = await checkPermission(for: browser)
        }
    }

    /// Legacy entry point for existing callers. Checks Safari.
    @MainActor
    func checkAutomationPermission() async -> Bool {
        isChecking = true
        defer { isChecking = false }
        return await checkPermission(for: .safari)
    }

    // MARK: - Settings

    /// Open System Settings to the Automation privacy pane.
    @MainActor
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Status Messages

    /// User-facing message for a specific browser.
    func statusMessage(for browser: Browser) -> String {
        if !browser.supportsReadTabs {
            return "ℹ️  Tab reading not available"
        }
        if permissions[browser.rawValue] == true {
            return "✅ Automation access granted"
        }
        return "⚠️  Automation access needed"
    }

    /// Legacy status message (Safari-specific).
    var statusMessage: String {
        statusMessage(for: .safari)
    }
}