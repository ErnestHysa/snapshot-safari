import Foundation
import SwiftUI
import Combine
import Sparkle

// MARK: - Updater Controller

/// Manages Sparkle auto-updates. Uses the standard updater controller.
/// All Sparkle API calls must happen on the main actor.
@MainActor
final class SparkleUpdater {
    static let shared = SparkleUpdater()

    let updaterController: SPUStandardUpdaterController

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

// MARK: - Notification Names

/// Sparkle 2.x defines its notification names as global NSString constants.
/// We bridge them to NSNotification.Name here.
private extension NSNotification.Name {
    static let sparkleUpdateStarted = NSNotification.Name("SPUUpdaterDidStartCheckingForUpdatesNotification")
    static let sparkleUpdateFinished = NSNotification.Name("SPUUpdaterDidFinishCheckingForUpdatesNotification")
}

// MARK: - Observable Wrapper for SwiftUI

/// Observable wrapper so SwiftUI views can observe Sparkle's state.
/// Uses Combine publishers to avoid @objc selectors (since @Observable classes don't inherit NSObject).
@MainActor
@Observable
final class SparkleUpdateChecker {
    static let shared = SparkleUpdateChecker()

    var canCheckForUpdates = false
    var isChecking = false

    private let updater: SPUUpdater
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let updater = SparkleUpdater.shared.updaterController.updater
        self.updater = updater
        self.canCheckForUpdates = updater.canCheckForUpdates

        // Observe KVO changes to canCheckForUpdates via Combine
        updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)

        // Observe update check lifecycle notifications via Combine
        NotificationCenter.default.publisher(for: .sparkleUpdateStarted, object: updater)
            .sink { [weak self] _ in
                self?.isChecking = true
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sparkleUpdateFinished, object: updater)
            .sink { [weak self] _ in
                self?.isChecking = false
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        SparkleUpdater.shared.checkForUpdates()
    }
}
