import Foundation
import SwiftData
import SwiftUI

// MARK: - Sync Service

/// Manages iCloud sync status and provides observable state for the UI.
@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    var isSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: Self.syncEnabledKey)
        }
    }

    var lastSyncDate: Date? {
        didSet {
            UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)
        }
    }

    var syncStatusMessage: String {
        guard isSyncEnabled else { return "iCloud sync is disabled" }
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
}
