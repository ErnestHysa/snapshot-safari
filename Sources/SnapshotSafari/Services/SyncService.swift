import Foundation
import SwiftData
import SwiftUI

// MARK: - Sync Service

/// Manages iCloud sync status and provides observable state for the UI.
@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    /// Whether the user has opted into iCloud sync in settings.
    var isSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: Self.syncEnabledKey)
        }
    }

    /// Whether CloudKit is actually available on this device (signed into iCloud, container provisioned).
    /// Set by SnapshotSafariApp.init() after attempting to create a cloud-backed ModelContainer.
    var isCloudAvailable: Bool = false

    /// Whether sync is both enabled by the user AND available on this device.
    var isSyncing: Bool {
        isSyncEnabled && isCloudAvailable
    }

    var lastSyncDate: Date? {
        didSet {
            UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)
        }
    }

    var syncStatusMessage: String {
        guard isSyncEnabled else { return "iCloud sync is disabled" }
        if !isCloudAvailable {
            return "iCloud unavailable — sign into iCloud in System Settings"
        }
        if let lastSync = lastSyncDate {
            return "Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))"
        }
        return "iCloud sync is enabled"
    }

    private static let syncEnabledKey = "iCloudSyncEnabled"
    private static let lastSyncKey = "iCloudLastSyncDate"

    private init() {
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
        self.lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    /// The CloudKit container identifier based on bundle ID
    var cloudKitContainerIdentifier: String {
        "iCloud.com.ernest.snapshot-safari"
    }

    /// Whether CloudKit is configured (for use by ModelConfiguration)
    var isCloudKitConfigured: Bool {
        isSyncEnabled
    }

    /// Mark a sync as having occurred (called after a successful cloud-backed snapshot operation)
    func markSyncOccurred() {
        lastSyncDate = Date()
    }
}
