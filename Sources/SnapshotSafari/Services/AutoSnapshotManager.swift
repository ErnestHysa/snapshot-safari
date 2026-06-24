import Foundation
import SwiftUI

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

    private weak var snapshotService: SnapshotService?
    private var loopTask: Task<Void, Never>?

    private static let enabledKey = "autoSnapshotEnabled"
    private static let intervalKey = "autoSnapshotInterval"
    private static let customKey = "autoSnapshotCustom"

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
            _ = try await service.takeSnapshot(isAuto: true)
        } catch {
            // Silently fail for auto-snapshots — Safari might just not be running
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
