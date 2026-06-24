import Testing
import Foundation
@testable import SnapshotSafari

// MARK: - SyncService Tests

@MainActor
struct SyncServiceTests {

    /// Reset the shared SyncService to clean defaults before each test.
    /// SyncService is a singleton with UserDefaults persistence, so tests
    /// must explicitly reset mutable state to avoid cross-test contamination.
    private func resetService() {
        SyncService.shared.isSyncEnabled = false
        SyncService.shared.isCloudAvailable = false
        SyncService.shared.lastSyncDate = nil
    }

    // MARK: - Default State

    @Test("sync is disabled by default")
    func defaultDisabled() {
        resetService()
        #expect(SyncService.shared.isSyncEnabled == false)
    }

    @Test("isCloudAvailable defaults to false")
    func cloudAvailableDefault() {
        resetService()
        #expect(SyncService.shared.isCloudAvailable == false)
    }

    @Test("isSyncing is false when sync is not enabled")
    func isSyncingDisabled() {
        resetService()
        SyncService.shared.isSyncEnabled = false
        SyncService.shared.isCloudAvailable = false
        #expect(SyncService.shared.isSyncing == false)
    }

    @Test("isSyncing is false when cloud is not available")
    func isSyncingCloudUnavailable() {
        resetService()
        SyncService.shared.isSyncEnabled = true
        SyncService.shared.isCloudAvailable = false
        #expect(SyncService.shared.isSyncing == false)
    }

    @Test("isSyncing is true only when both enabled and available")
    func isSyncingBoth() {
        resetService()
        SyncService.shared.isSyncEnabled = true
        SyncService.shared.isCloudAvailable = true
        #expect(SyncService.shared.isSyncing == true)
    }

    // MARK: - Container Identifier

    @Test("cloudKitContainerIdentifier matches container format")
    func containerIdentifier() {
        resetService()
        #expect(SyncService.shared.cloudKitContainerIdentifier == "iCloud.com.ernest.snapshot-safari")
    }

    @Test("isCloudKitConfigured mirrors isSyncEnabled")
    func cloudKitConfigured() {
        resetService()
        SyncService.shared.isSyncEnabled = true
        #expect(SyncService.shared.isCloudKitConfigured == true)

        SyncService.shared.isSyncEnabled = false
        #expect(SyncService.shared.isCloudKitConfigured == false)
    }

    // MARK: - Status Messages

    @Test("syncStatusMessage shows disabled when sync is off")
    func statusDisabled() {
        resetService()
        SyncService.shared.isSyncEnabled = false
        #expect(SyncService.shared.syncStatusMessage == "iCloud sync is disabled")
    }

    @Test("syncStatusMessage shows unavailable when cloud not available")
    func statusCloudUnavailable() {
        resetService()
        SyncService.shared.isSyncEnabled = true
        SyncService.shared.isCloudAvailable = false
        #expect(SyncService.shared.syncStatusMessage == "iCloud unavailable — sign into iCloud in System Settings")
    }

    @Test("syncStatusMessage shows enabled when sync is on and cloud available")
    func statusEnabled() {
        resetService()
        SyncService.shared.isSyncEnabled = true
        SyncService.shared.isCloudAvailable = true
        SyncService.shared.lastSyncDate = nil
        #expect(SyncService.shared.syncStatusMessage == "iCloud sync is enabled")
    }

    @Test("syncStatusMessage shows last sync date after markSyncOccurred")
    func statusWithLastSync() {
        resetService()
        SyncService.shared.isSyncEnabled = true
        SyncService.shared.isCloudAvailable = true
        SyncService.shared.markSyncOccurred()

        #expect(SyncService.shared.lastSyncDate != nil)
        #expect(SyncService.shared.syncStatusMessage.hasPrefix("Last synced:"))
    }

    // MARK: - markSyncOccurred

    @Test("markSyncOccurred updates lastSyncDate to now")
    func markSync() {
        resetService()
        let before = Date()
        SyncService.shared.markSyncOccurred()
        let after = Date()

        #expect(SyncService.shared.lastSyncDate != nil)
        if let lastSync = SyncService.shared.lastSyncDate {
            #expect(lastSync >= before)
            #expect(lastSync <= after)
        }
    }

    // MARK: - Toggle State

    @Test("toggling sync enabled works correctly")
    func toggleSync() {
        resetService()
        SyncService.shared.isSyncEnabled = true
        #expect(SyncService.shared.isSyncEnabled == true)

        SyncService.shared.isSyncEnabled = false
        #expect(SyncService.shared.isSyncEnabled == false)
    }

    @Test("lastSyncDate can be set and read back")
    func lastSyncDateSet() {
        resetService()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        SyncService.shared.lastSyncDate = date
        #expect(SyncService.shared.lastSyncDate == date)
    }
}
