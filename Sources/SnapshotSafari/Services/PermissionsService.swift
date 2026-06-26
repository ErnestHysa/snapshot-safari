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
    ///
    /// IMPORTANT: The probe must do something that actually requires
    /// dispatching an AppleEvent to Safari — accessing `.name` on the
    /// application object is a local property lookup and does NOT trigger
    /// TCC. Reading `windows.length` forces Safari to handle a real
    /// AppleEvent and is the cheapest probe that does so.
    @MainActor
    func checkAutomationPermission() async -> Bool {
        isChecking = true
        defer { isChecking = false }

        NSLog("PROBE: checkAutomationPermission called")

        // Is Safari running? If not, the probe will hang on AppleEvent
        // delivery. Treat that as "not granted" so we don't show a false
        // positive when Safari is closed.
        let safariRunning = isSafariRunning()
        NSLog("PROBE: Safari running = \(safariRunning)")
        if !safariRunning {
            logger.debug("Safari is not running — treating as not granted")
            hasAutomationPermission = false
            return false
        }

        let script = """
        function run() {
            var safari = Application('Safari');
            // Reading windows.length forces Safari to handle a real
            // AppleEvent (kAEGETDATA / GetData), which is what triggers
            // the TCC prompt on first contact. Calling .name() alone
            // does NOT dispatch.
            //
            // We coerce to a String because returning a raw Int from
            // JXA can yield errAECantPutAway (-1712) when the reply
            // descriptor tries to put the value into a non-Int box.
            return String(safari.windows.length);
        }
        """

        let result = OSAScript(source: script, language: OSALanguage(forName: "JavaScript")!)
        var error: NSDictionary?
        let outcome = result.executeAndReturnError(&error)
        let outcomeStr = String(describing: outcome)
        let errorStr = String(describing: error)
        NSLog("PROBE outcome: \(outcomeStr), error: \(errorStr)")
        logger.debug("Probe raw outcome: \(outcomeStr), error: \(errorStr)")

        if let error {
            let code = (error[OSAScriptErrorNumberKey] as? Int) ?? 0
            let message = (error[OSAScriptErrorMessageKey] as? String) ?? ""
            NSLog("PROBE: error code=\(code), message=\(message)")
            // errAEEventNotHandled (-1708) is what Safari returns when the
            // user has not (or has denied) granted Automation access.
            // errOSANoUserInteractionAllowed (-1750) is what we get if the
            // call happens while Safari is frontmost with no UI event.
            // applicationNotRunningErr (-600) is what the AppleEvent
            // manager returns when the sandbox or TCC blocks dispatch —
            // treating this as "not granted" is correct: the AppleEvent
            // did not actually reach Safari.
            // errAECantPutAway (-1712) can happen on success or failure;
            // treat as not granted (conservative).
            let grantedCodes: Set<Int> = []
            hasAutomationPermission = grantedCodes.contains(code)
        } else if let countStr = outcome?.stringValue {
            // Successful dispatch and Safari told us how many windows it
            // has — that means the AppleEvent was delivered, which means
            // we have permission. The script returns a String, not a
            // number, because raw Int returns from JXA can fail with
            // errAECantPutAway (-1712) when the reply descriptor tries
            // to put the value into the wrong key form.
            NSLog("PROBE: succeeded — Safari reports \(countStr) windows")
            hasAutomationPermission = true
        } else {
            NSLog("PROBE: no error and no outcome — treating as not granted")
            hasAutomationPermission = false
        }

        return hasAutomationPermission
    }

    /// Whether Safari is running. Used to skip the probe when it's not,
    /// since sending an AppleEvent to a non-running app will block
    /// until the user opens it.
    private func isSafariRunning() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { $0.bundleIdentifier == "com.apple.Safari" }
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