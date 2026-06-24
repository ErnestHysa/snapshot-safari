import Foundation
import Security
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
        isSyncEnabled && isCloudAvailable && iCloudEntitled
    }

    var lastSyncDate: Date? {
        didSet {
            UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)
        }
    }

    var syncStatusMessage: String {
        if !iCloudEntitled {
            return "iCloud sync requires a developer build — download the public build from GitHub releases"
        }
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
        isSyncEnabled && iCloudEntitled
    }

    /// Whether this build of the app carries the iCloud / CloudKit entitlements
    /// required to actually use CloudKit. Public ad-hoc-signed builds do NOT
    /// carry them (AMFI refuses to load such binaries on macOS). Developer
    /// builds signed with a Developer ID can include them.
    ///
    /// Detected at runtime by reading the embedded entitlements of the running
    /// binary. Cached after first read — entitlements don't change mid-process.
    /// Tests inject a deterministic value via `setICloudEntitledForTesting`.
    var iCloudEntitled: Bool {
        Self.overrideICloudEntitled ?? Self.cachedICloudEntitled
    }

    private static let cachedICloudEntitled: Bool = {
        // CloudKit entitlements require the iCloud container + services keys.
        // Their absence is the signal that this build cannot use iCloud.
        let hasContainer = SyncService.currentProcessHasEntitlement(
            "com.apple.developer.icloud-container-identifiers"
        )
        let hasServices = SyncService.currentProcessHasEntitlement(
            "com.apple.developer.icloud-services"
        )
        return hasContainer && hasServices
    }()

    /// Test-only override. Setting to `nil` restores the runtime-detected value.
    static var overrideICloudEntitled: Bool? = nil

    /// Test helper. Pass `nil` to restore the runtime-detected value.
    @MainActor
    static func setICloudEntitledForTesting(_ value: Bool?) {
        overrideICloudEntitled = value
    }

    /// Read a single entitlement key from the current process's signed entitlements.
    /// Returns true if the entitlement is present (regardless of value).
    private static func currentProcessHasEntitlement(_ key: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        return value != nil
    }

    /// Mark a sync as having occurred (called after a successful cloud-backed snapshot operation)
    func markSyncOccurred() {
        lastSyncDate = Date()
    }
}