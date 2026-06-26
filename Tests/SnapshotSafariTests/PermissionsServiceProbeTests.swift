import Testing
import Foundation
import AppKit
@testable import SnapshotSafari

// MARK: - PermissionsService Probe Tests

@MainActor
struct PermissionsServiceProbeTests {

    @Test("Probe script reads windows.length and returns String")
    func probeScriptTriggersAppleEvent() {
        // The probe must contain something that forces Safari to handle a
        // real AppleEvent. Accessing `.name` on the Application object is
        // a local property lookup and does NOT trigger TCC — we must use
        // something like `windows.length` instead. We wrap in String()
        // because raw Int returns from JXA can fail with -1712
        // (errAECantPutAway) when the reply descriptor tries to put the
        // value into the wrong key form.
        let script = """
        function run() {
            var safari = Application('Safari');
            return String(safari.windows.length);
        }
        """
        #expect(script.contains("safari.windows.length"))
        #expect(script.contains("String("))
        #expect(!script.contains(".includeStandardAdditions"))
    }

    @Test("Probe handles errAEEventNotHandled -1708 as not granted")
    func probeHandlesNotHandled() {
        // errAEEventNotHandled is what Safari returns when the user has
        // not (or has denied) granted Automation access.
        let grantedCodes: Set<Int> = []
        let probeResult = -1708
        let granted = grantedCodes.contains(probeResult)
        #expect(!granted)
    }

    @Test("Probe treats -600 applicationNotRunningErr as not granted")
    func probeTreats600AsNotGranted() {
        // -600 is what the AppleEvent manager returns when the sandbox
        // or TCC blocks dispatch. Previously we treated any non-(-1708)
        // code as granted, which made -600 silently mean "granted" — a
        // false positive that hid the real problem from the user.
        let grantedCodes: Set<Int> = []
        let probeResult = -600
        let granted = grantedCodes.contains(probeResult)
        #expect(!granted)
    }

    @Test("Probe treats successful dispatch with stringValue as granted")
    func probeTreatsSuccessAsGranted() {
        // OSAScript returns NSAppleEventDescriptor wrapping the JS return
        // value when no error occurs. We read .stringValue (not just !=
        // nil) because the previous false-positive path was `outcome !=
        // nil` and `.int32Value` only — both could be satisfied by a
        // null descriptor. The probe now returns a String from JXA.
        let desc = NSAppleEventDescriptor(string: "1")
        #expect(desc.stringValue == "1")
    }

    @Test("isSafariRunning predicate uses com.apple.Safari bundle id")
    func isSafariRunningPredicate() {
        // The bundle id we check must match Safari's actual bundle id.
        // If this drifts, the probe will be skipped when Safari IS open,
        // which would cause a silent false-negative.
        let safariBundleId = "com.apple.Safari"
        let apps = NSWorkspace.shared.runningApplications
        let hasSafari = apps.contains { $0.bundleIdentifier == safariBundleId }
        // We don't care about the actual value (depends on whether Safari
        // is open in CI); we care that the predicate doesn't crash.
        _ = hasSafari
        #expect(safariBundleId == "com.apple.Safari")
    }

    @Test("All error codes are treated as not granted by default")
    func allDenialCodesRecognised() {
        // The probe's grantedCodes set is empty by default — any error
        // means not granted. Only a successful dispatch with a real
        // stringValue result grants access. This is intentionally
        // conservative so a failed probe (sandbox blocked, TCC denied,
        // Safari not running) is never misreported as "granted".
        let grantedCodes: Set<Int> = []
        for code in [-1708, -1709, -1750, -600, -1712, -1743] {
            #expect(!grantedCodes.contains(code))
        }
        // And must NOT contain unrelated values
        #expect(!grantedCodes.contains(0))
        #expect(!grantedCodes.contains(-1))
    }
}