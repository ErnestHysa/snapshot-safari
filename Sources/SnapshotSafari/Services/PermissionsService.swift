import Foundation
import AppKit
import ApplicationServices

// MARK: - Permissions

@Observable
final class PermissionsService {
    var hasAutomationPermission: Bool = false
    var isChecking: Bool = false

    /// Check if we have Automation permission for Safari by attempting a simple script
    @MainActor
    func checkAutomationPermission() async -> Bool {
        isChecking = true
        defer { isChecking = false }

        // Attempt a minimal AppleScript to test Automation access to Safari
        let script = "tell application \"System Events\" to get name of every process whose name is \"Safari\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            hasAutomationPermission = process.terminationStatus == 0
        } catch {
            hasAutomationPermission = false
        }

        return hasAutomationPermission
    }

    /// Open System Settings to the Automation privacy pane
    @MainActor
    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    var statusMessage: String {
        if hasAutomationPermission {
            return "✅ Automation access granted"
        }
        return "⚠️  Automation access needed"
    }
}
