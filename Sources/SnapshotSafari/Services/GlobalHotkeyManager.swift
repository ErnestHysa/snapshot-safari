import Foundation
import AppKit
import ApplicationServices
import os.log

// MARK: - Global Hotkey Manager

/// Registers a system-wide global hotkey that fires even when SnapshotSafari
/// is not the frontmost application.
///
/// Uses `NSEvent.addGlobalMonitorForEvents` which requires the app to be
/// trusted for Accessibility (granted in System Settings → Privacy & Security
/// → Accessibility). Global monitors observe events dispatched to OTHER
/// applications, so there is no double-fire with the menu bar Cmd+Shift+K
/// shortcut that handles the frontmost-app case.
///
/// `AXIsProcessTrusted()` checks status; if not granted, the manager is a
/// no-op. The user can grant it at any time via System Settings.
final class GlobalHotkeyManager: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.ernest.snapshot-safari", category: "GlobalHotkey")
    private var monitor: Any?
    private var activationObserver: NSObjectProtocol?

    /// macOS key code for the 'K' key.
    private static let kKeyCode: UInt16 = 40

    /// Whether the user has granted Accessibility permission.
    /// Must be called on the main thread.
    @MainActor
    var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Start / Stop

    /// Register the global Cmd+Shift+K hotkey. No-op if already registered.
    /// If Accessibility permission hasn't been granted yet, the monitor
    /// will retry on each app activation so the user doesn't need to
    /// restart after granting permission in System Settings.
    @MainActor
    func start() {
        guard monitor == nil else {
            logger.debug("Global hotkey monitor already running")
            return
        }

        // Try to start immediately
        tryStartMonitor()

        // Retry on each activation (user might grant permission later)
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tryStartMonitor()
            }
        }
    }

    /// Remove the global hotkey monitor and activation observer.
    @MainActor
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            logger.debug("Global hotkey monitor stopped")
        }
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
            activationObserver = nil
        }
    }

    // MARK: - Private

    @MainActor
    private func tryStartMonitor() {
        guard monitor == nil else { return }
        guard hasPermission else {
            logger.debug("Accessibility permission not granted — global hotkey disabled")
            return
        }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }

            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
               event.keyCode == Self.kKeyCode {
                self.logger.debug("Global hotkey Cmd+Shift+K pressed, posting takeSnapshot")
                NotificationCenter.default.post(name: .takeSnapshot, object: nil)
            }
        }

        logger.debug("Global hotkey monitor started (Cmd+Shift+K)")
    }

    deinit {
        Task { @MainActor [monitor, activationObserver] in
            if let m = monitor { NSEvent.removeMonitor(m) }
            if let o = activationObserver { NotificationCenter.default.removeObserver(o) }
        }
    }

    // MARK: - Permission Prompt

    /// Present a dialog asking the user to grant Accessibility permission,
    /// with a button to open System Settings directly.
    @MainActor
    func promptForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Needed"
        alert.informativeText = """
        Snapshot Safari needs Accessibility access to activate the global shortcut \
        Cmd+Shift+K, so you can take a snapshot even when another app (like Chrome) \
        is frontmost.

        Open System Settings → Privacy & Security → Accessibility, \
        then enable Snapshot Safari.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
