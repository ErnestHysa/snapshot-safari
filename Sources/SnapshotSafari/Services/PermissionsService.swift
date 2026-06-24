import Foundation
import AppKit
import ApplicationServices
import OSAKit
import os.log

/// Tracks whether Snapshot Safari has been granted Automation access to Safari.
///
/// On modern macOS, when an app sends an AppleEvent to another app for the first
/// time, the system automatically prompts the user to grant permission. The
/// result is recorded against THIS bundle id (`com.ernest.snapshot-safari`) in
/// System Settings → Privacy & Security → Automation — NOT against `osascript`,
/// which is the path the older osascript-spawning code took.
///
/// The check here is best-effort: we attempt a minimal "are you there?" probe
/// against Safari and report success/failure based on whether the AppleEvent was
/// delivered. We intentionally do NOT try to read TCC.db directly — that's not
/// supported API and the probe is more accurate anyway.
@Observable
final class PermissionsService {
    var hasAutomationPermission: Bool = false
    var isChecking: Bool = false

    private let logger = Logger(subsystem: "com.ernest.snapshot-safari", category: "Permissions")

    /// Probe by attempting to send a minimal AppleEvent to Safari.
    /// On first run this triggers macOS's permission prompt for our bundle id;
    /// subsequent runs return quickly based on the recorded TCC decision.
    @MainActor
    func checkAutomationPermission() async -> Bool {
        isChecking = true
        defer { isChecking = false }

        let script = """
        function run() {
            var safari = Application('Safari');
            safari.includeStandardAdditions = true;
            return safari.name();
        }
        """

        let result = OSAScript(source: script, language: OSALanguage(forName: "JavaScript")!)
        var error: NSDictionary?
        let outcome = result.executeAndReturnError(&error)

        if let error {
            let code = (error[OSAScriptErrorNumberKey] as? Int) ?? 0
            let message = (error[OSAScriptErrorMessageKey] as? String) ?? ""
            logger.debug("Probe AppleEvent outcome — code: \(code), message: \(message)")
            // errAEEventNotHandled (-1708) is what Safari returns when the
            // user has not (or has denied) granted Automation access.
            hasAutomationPermission = (code != -1708 && code != -1709 && code != -1750)
        } else if outcome != nil {
            hasAutomationPermission = true
        } else {
            hasAutomationPermission = false
        }

        return hasAutomationPermission
    }

    /// Open System Settings to the Automation privacy pane.
    /// On macOS 13+ the deep-link uses `x-apple.systempreferences:` URL scheme.
    @MainActor
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// User-facing message reflecting current permission state.
    var statusMessage: String {
        if hasAutomationPermission {
            return "✅ Automation access granted"
        }
        return "⚠️  Automation access needed"
    }
}