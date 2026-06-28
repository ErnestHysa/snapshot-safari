import Foundation
import SwiftUI

/// Which browser(s) to target for automatic snapshots.
/// Uses a struct rather than an enum so specific-browser targets are
/// generated dynamically from installed browsers.
struct AutoSnapshotTarget: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let icon: String
    let browser: Browser?

    private init(id: String, label: String, icon: String, browser: Browser?) {
        self.id = id
        self.label = label
        self.icon = icon
        self.browser = browser
    }

    // MARK: - Static Targets

    static let frontmost = AutoSnapshotTarget(
        id: "frontmost",
        label: "Frontmost Browser",
        icon: "rectangle.badge.checkmark",
        browser: nil
    )

    static let allRunning = AutoSnapshotTarget(
        id: "allRunning",
        label: "All Running Browsers",
        icon: "square.grid.2x2",
        browser: nil
    )

    /// Targets for each installed readable browser.
    static var installedBrowserTargets: [AutoSnapshotTarget] {
        Browser.allCases
            .filter { $0.isInstalled && $0.supportsReadTabs }
            .map { browser in
                AutoSnapshotTarget(
                    id: "browser:\(browser.rawValue)",
                    label: browser.displayName,
                    icon: browser.iconName,
                    browser: browser
                )
            }
    }

    /// All available targets: frontmost + all running + each installed browser.
    static var all: [AutoSnapshotTarget] {
        [.frontmost, .allRunning] + installedBrowserTargets
    }

    /// Resolve a stored id string back to a target.
    static func resolve(id: String) -> AutoSnapshotTarget {
        if id == frontmost.id { return .frontmost }
        if id == allRunning.id { return .allRunning }
        for target in installedBrowserTargets {
            if target.id == id { return target }
        }
        // Migration from old enum raw values (pre-2.0)
        if id == "Safari", let t = installedBrowserTargets.first(where: { $0.browser == .safari }) { return t }
        if id == "Chrome", let t = installedBrowserTargets.first(where: { $0.browser == .chrome }) { return t }
        return .allRunning // sensible default
    }
}

@Observable
final class AutoSnapshotManager: @unchecked Sendable {
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            restartLoop()
        }
    }

    var interval: TimeInterval {
        didSet {
            UserDefaults.standard.set(interval, forKey: Self.intervalKey)
            restartLoop()
        }
    }

    var isCustomInterval: Bool {
        didSet {
            UserDefaults.standard.set(isCustomInterval, forKey: Self.customKey)
        }
    }

    var target: AutoSnapshotTarget {
        didSet {
            UserDefaults.standard.set(target.id, forKey: Self.targetKey)
        }
    }

    private weak var snapshotService: SnapshotService?
    private var loopTask: Task<Void, Never>?

    private static let enabledKey = "autoSnapshotEnabled"
    private static let intervalKey = "autoSnapshotInterval"
    private static let customKey = "autoSnapshotCustom"
    private static let targetKey = "autoSnapshotTarget"

    static let presets: [(label: String, interval: TimeInterval)] = [
        ("30 min", 1800),
        ("1 hour", 3600),
        ("2 hours", 7200),
        ("4 hours", 14400),
    ]

    init(snapshotService: SnapshotService?) {
        self.snapshotService = snapshotService
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.interval = UserDefaults.standard.double(forKey: Self.intervalKey).nonZero ?? 3600
        self.isCustomInterval = UserDefaults.standard.bool(forKey: Self.customKey)
        let targetId = UserDefaults.standard.string(forKey: Self.targetKey) ?? "allRunning"
        self.target = AutoSnapshotTarget.resolve(id: targetId)

        if isEnabled {
            startLoop()
        }
    }

    // MARK: - Public Control

    func start() { startLoop() }
    func stop() { stopLoop() }

    // MARK: - Loop

    private func startLoop() {
        stopLoop()
        guard isEnabled else { return }

        loopTask = Task { [weak self] in
            guard let self else { return }

            let interval = self.interval // Capture by value (Sendable)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.takeAutoSnapshot()
            }
        }
    }

    func restartLoop() {
        if isEnabled {
            startLoop()
        } else {
            stopLoop()
        }
    }

    func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Snapshot

    @MainActor
    private func takeAutoSnapshot() async {
        guard let service = snapshotService else { return }
        do {
            switch target.id {
            case "frontmost":
                guard let frontmost = Browser.frontmostBrowser, frontmost.supportsReadTabs else {
                    return
                }
                _ = try await service.takeSnapshot(browser: frontmost, isAuto: true)
            case "allRunning":
                _ = try await service.takeSnapshotOfAllBrowsers(isAuto: true)
            default:
                if let browser = target.browser {
                    _ = try await service.takeSnapshot(browser: browser, isAuto: true)
                }
            }
        } catch {
            // Silently fail for auto-snapshots — browser might just not be running
            print("Auto-snapshot failed: \(error.localizedDescription)")
        }
    }

    deinit {
        loopTask?.cancel()
    }
}

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
