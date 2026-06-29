import Foundation
import SwiftData

@MainActor
final class SnapshotService {
    private let modelContext: ModelContext
    private let bridgeProvider: @Sendable (Browser) -> any BrowserBridge

    init(modelContext: ModelContext, bridgeProvider: @escaping @Sendable (Browser) -> any BrowserBridge = BrowserBridgeFactory.create) {
        self.modelContext = modelContext
        self.bridgeProvider = bridgeProvider
    }

    // MARK: - Create

    /// Takes a new snapshot of all open tabs from the specified browser.
    @discardableResult
    func takeSnapshot(browser: Browser? = nil, isAuto: Bool = false) async throws -> Snapshot {
        let targetBrowser = browser ?? .frontmostBrowser ?? .safari
        let bridge = bridgeProvider(targetBrowser)

        let tabs: [BrowserTab]
        do {
            tabs = try await bridge.readAllTabs()
        } catch let error as BrowserBridgeError {
            throw error
        } catch {
            throw error
        }

        guard !tabs.isEmpty else {
            throw BrowserBridgeError.noTabsFound
        }

        let tabEntries = tabs.map { tab in
            TabEntry(
                url: tab.url ?? "about:blank",
                title: tab.title,
                windowIndex: tab.windowIndex,
                index: tab.index,
                browserId: tab.browserId
            )
        }

        let name = AutoNamer.generateName(
            tabCount: tabEntries.count,
            isAuto: isAuto,
            browserName: targetBrowser.shortName
        )
        let snapshot = Snapshot(name: name, tabs: tabEntries, isAutoSnapshot: isAuto)

        modelContext.insert(snapshot)
        try modelContext.save()

        return snapshot
    }

    /// Takes a snapshot of ALL running browsers that support tab reading.
    /// Tabs are tagged with their source browser and stored in a single snapshot.
    /// Throws `CapturePartialFailure` when some browsers succeed but others fail.
    @discardableResult
    func takeSnapshotOfAllBrowsers(isAuto: Bool = false) async throws -> Snapshot {
        let readableBrowsers = Browser.readableRunningBrowsers

        guard !readableBrowsers.isEmpty else {
            throw BrowserBridgeError.noTabsFound
        }

        // Collect tabs from all readable browsers concurrently,
        // tracking per-browser success/failure for partial error surfacing.
        var allTabs: [BrowserTab] = []
        var failures: [(Browser, Error)] = []

        await withTaskGroup(of: Result<[BrowserTab], BrowserCaptureFailure>.self) { group in
            for browser in readableBrowsers {
                group.addTask { [bridgeProvider] in
                    let bridge = bridgeProvider(browser)
                    do {
                        let tabs = try await bridge.readAllTabs()
                        return .success(tabs)
                    } catch {
                        return .failure(BrowserCaptureFailure(browser: browser, error: error))
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let tabs):
                    allTabs.append(contentsOf: tabs)
                case .failure(let failure):
                    failures.append((failure.browser, failure.error))
                }
            }
        }

        // If nothing was captured at all
        if allTabs.isEmpty {
            if let first = failures.first {
                throw first.1
            }
            throw BrowserBridgeError.noTabsFound
        }

        let tabEntries = allTabs.map { tab in
            TabEntry(
                url: tab.url ?? "about:blank",
                title: tab.title,
                windowIndex: tab.windowIndex,
                index: tab.index,
                browserId: tab.browserId
            )
        }

        let browserNames = Set(tabEntries.compactMap { Browser(rawValue: $0.browserId)?.shortName }).sorted()
        let name = AutoNamer.generateName(
            tabCount: tabEntries.count,
            isAuto: isAuto,
            browserName: browserNames.joined(separator: " + ")
        )
        let snapshot = Snapshot(name: name, tabs: tabEntries, isAutoSnapshot: isAuto)

        modelContext.insert(snapshot)
        try modelContext.save()

        if !failures.isEmpty {
            throw CapturePartialFailure(snapshot: snapshot, failedBrowsers: failures)
        }

        return snapshot
    }

    // MARK: - Read

    /// All snapshots that are not trashed
    func fetchAllSnapshots() -> [Snapshot] {
        let descriptor = FetchDescriptor<Snapshot>(
            predicate: #Predicate { !$0.isTrashed },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Only trashed snapshots (recently deleted)
    func fetchTrashedSnapshots() -> [Snapshot] {
        let descriptor = FetchDescriptor<Snapshot>(
            predicate: #Predicate { $0.isTrashed },
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Search across non-trashed snapshots
    func searchSnapshots(query: String) -> [Snapshot] {
        guard !query.isEmpty else { return fetchAllSnapshots() }

        let lowercased = query.lowercased()

        let descriptor = FetchDescriptor<Snapshot>(
            predicate: #Predicate { !$0.isTrashed },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let all = try? modelContext.fetch(descriptor) else { return [] }

        return all.filter { snapshot in
            snapshot.name.localizedCaseInsensitiveContains(lowercased)
            || snapshot.tabs.contains { tab in
                tab.title.localizedCaseInsensitiveContains(lowercased)
                || tab.url.localizedCaseInsensitiveContains(lowercased)
                || tab.domain.localizedCaseInsensitiveContains(lowercased)
            }
        }
    }

    // MARK: - Update / Rename

    func renameSnapshot(_ snapshot: Snapshot, to newName: String) {
        snapshot.name = newName
        snapshot.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Soft Delete (Undo-capable)

    /// Move to trash instead of permanent delete
    func trashSnapshot(_ snapshot: Snapshot) {
        snapshot.isTrashed = true
        snapshot.deletedAt = Date()
        try? modelContext.save()
    }

    func trashSnapshots(_ snapshots: [Snapshot]) {
        for snapshot in snapshots {
            snapshot.isTrashed = true
            snapshot.deletedAt = Date()
        }
        try? modelContext.save()
    }

    /// Restore from trash
    func restoreFromTrash(_ snapshot: Snapshot) {
        snapshot.isTrashed = false
        snapshot.deletedAt = nil
        try? modelContext.save()
    }

    func restoreAllFromTrash() {
        let trashed = fetchTrashedSnapshots()
        for snapshot in trashed {
            snapshot.isTrashed = false
            snapshot.deletedAt = nil
        }
        try? modelContext.save()
    }

    /// Permanently delete (removes from SwiftData)
    func permanentlyDelete(_ snapshot: Snapshot) {
        modelContext.delete(snapshot)
        try? modelContext.save()
    }

    func permanentlyDeleteAllTrashed() {
        let trashed = fetchTrashedSnapshots()
        for snapshot in trashed {
            modelContext.delete(snapshot)
        }
        try? modelContext.save()
    }

    /// Auto-cleanup trash older than 30 days
    func cleanUpOldTrash() {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        // Fetch all trashed snapshots, filter in-memory
        let trashed = fetchTrashedSnapshots()
        let oldOnes = trashed.filter { ($0.deletedAt ?? Date.distantPast) < thirtyDaysAgo }
        for snapshot in oldOnes {
            modelContext.delete(snapshot)
        }
        if !oldOnes.isEmpty {
            try? modelContext.save()
        }
    }

    // MARK: - Comparison

    /// Compute the diff between two snapshots
    func compareSnapshots(_ older: Snapshot, _ newer: Snapshot) -> SnapshotDiff {
        SnapshotDiff.compute(between: older, and: newer)
    }

    // MARK: - Export / Import

    /// Export a single snapshot to JSON data.
    func exportSnapshotToJSON(_ snapshot: Snapshot) throws -> Data {
        try SnapshotExport.create(from: [snapshot]).jsonData()
    }

    /// Export multiple snapshots to JSON data.
    func exportMultipleSnapshotsToJSON(_ snapshots: [Snapshot]) throws -> Data {
        try SnapshotExport.create(from: snapshots).jsonData()
    }

    /// Import snapshots from JSON data.
    /// Returns the number of snapshots imported.
    @discardableResult
    func importSnapshots(from jsonData: Data) throws -> Int {
        let export = try SnapshotExport.from(jsonData: jsonData)

        guard export.version == SnapshotExport.currentVersion else {
            throw ExportError.unsupportedVersion(export.version)
        }

        for exportedSnapshot in export.snapshots {
            let tabEntries = exportedSnapshot.tabs.map { tab in
                TabEntry(
                    url: tab.url,
                    title: tab.title,
                    windowIndex: tab.windowIndex,
                    index: tab.index
                )
            }

            let snapshot = Snapshot(
                name: exportedSnapshot.name,
                tabs: tabEntries,
                isAutoSnapshot: exportedSnapshot.isAutoSnapshot
            )
            // Preserve the original creation date
            snapshot.createdAt = exportedSnapshot.createdAt
            snapshot.updatedAt = exportedSnapshot.createdAt

            modelContext.insert(snapshot)
        }

        try modelContext.save()
        return export.snapshots.count
    }

    // MARK: - Export Errors

    enum ExportError: LocalizedError, Equatable {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                if version > SnapshotExport.currentVersion {
                    return "This file was created by a newer version of Snapshot Safari. Please update to import it."
                }
                return "Unsupported export format version \(version)."
            }
        }
    }

    /// Thrown when restoring a multi-browser snapshot where some browser groups
    /// succeeded but others failed. Carries the restored count for partial-success UX.
    struct RestorePartialFailure: LocalizedError {
        let totalRestored: Int
        let failedBrowsers: [(Browser, Error)]

        var errorDescription: String? {
            let label = totalRestored == 1 ? "tab" : "tabs"
            let details = failedBrowsers
                .map { "\($0.0.shortName) could not be restored — \($0.1.localizedDescription)" }
                .joined(separator: "; ")
            return "Restored \(totalRestored) \(label), but \(details)"
        }
    }

    /// Wraps a per-browser capture failure for use in `Result` types
    /// within `takeSnapshotOfAllBrowsers`.
    private struct BrowserCaptureFailure: Error {
        let browser: Browser
        let error: Error
    }

    /// Thrown when capturing tabs from all running browsers where some succeeded
    /// but others failed. Carries the persisted snapshot and failed browsers so
    /// the UI can both show the snapshot and display the partial-failure message.
    struct CapturePartialFailure: LocalizedError, @unchecked Sendable {
        let snapshot: Snapshot
        let failedBrowsers: [(Browser, Error)]

        var errorDescription: String? {
            let label = snapshot.tabCount == 1 ? "tab" : "tabs"
            let details = failedBrowsers
                .map { "\($0.0.shortName) could not be captured — \($0.1.localizedDescription)" }
                .joined(separator: "; ")
            return "Captured \(snapshot.tabCount) \(label) across browsers, but \(details)"
        }
    }

    // MARK: - Legacy Delete (for backward compat - delegates to trash)

    func deleteSnapshot(_ snapshot: Snapshot) {
        trashSnapshot(snapshot)
    }

    func deleteSnapshots(_ snapshots: [Snapshot]) {
        trashSnapshots(snapshots)
    }

    // MARK: - Restore

    enum RestoreMode: String, CaseIterable {
        case newWindow = "New Window"
        case currentWindow = "Current Window (append)"

        var bridgeMode: BrowserRestoreMode {
            switch self {
            case .newWindow: return .newWindow
            case .currentWindow: return .currentWindow
            }
        }
    }

    /// Restore a full snapshot to the specified browser.
    /// If `targetBrowser` is nil, each tab is restored to its original browser.
    @discardableResult
    func restoreSnapshot(_ snapshot: Snapshot, mode: RestoreMode, targetBrowser: Browser? = nil) async throws -> Int {
        if let target = targetBrowser {
            // Force all tabs into one browser
            let bridge = bridgeProvider(target)
            let tabs = snapshot.tabs.map { entry in
                BrowserTab(
                    url: entry.url,
                    title: entry.title,
                    windowIndex: entry.windowIndex,
                    index: entry.index,
                    browserId: target.rawValue
                )
            }
            let count = try await bridge.restoreTabs(tabs, mode: mode.bridgeMode)
            target.activate()
            return count
        } else {
            let groups = Dictionary(grouping: snapshot.tabs) { $0.browserId }
            return try await restoreGroups(groups, mode: mode)
        }
    }

    @discardableResult
    func restoreTabs(_ entries: [TabEntry], mode: RestoreMode, targetBrowser: Browser? = nil) async throws -> Int {
        if let target = targetBrowser {
            let bridge = bridgeProvider(target)
            let tabs = entries.map { entry in
                BrowserTab(
                    url: entry.url,
                    title: entry.title,
                    windowIndex: entry.windowIndex,
                    index: entry.index,
                    browserId: target.rawValue
                )
            }
            let count = try await bridge.restoreTabs(tabs, mode: mode.bridgeMode)
            target.activate()
            return count
        } else {
            let groups = Dictionary(grouping: entries) { $0.browserId }
            return try await restoreGroups(groups, mode: mode)
        }
    }

    // MARK: - Private Restore Helpers

    /// Restore tab groups to their original browsers. Handles partial failures
    /// by collecting them and throwing `RestorePartialFailure` when some succeed.
    func restoreGroups(_ groups: [String: [TabEntry]], mode: RestoreMode) async throws -> Int {
        var totalRestored = 0
        var failures: [(Browser, Error)] = []

        for (browserId, entries) in groups {
            guard let browser = Browser(rawValue: browserId) else { continue }
            let bridge = bridgeProvider(browser)
            let tabs = entries.map { entry in
                BrowserTab(
                    url: entry.url,
                    title: entry.title,
                    windowIndex: entry.windowIndex,
                    index: entry.index,
                    browserId: browserId
                )
            }
            do {
                let count = try await bridge.restoreTabs(tabs, mode: mode.bridgeMode)
                totalRestored += count
            } catch {
                failures.append((browser, error))
            }
        }

        // Activate the browser that had the most tabs
        if let dominant = groups.max(by: { $0.value.count < $1.value.count }),
           let browser = Browser(rawValue: dominant.key) {
            browser.activate()
        }

        if totalRestored == 0 {
            // Nothing restored at all — throw the first failure if available
            if let first = failures.first {
                throw first.1
            }
            throw BrowserBridgeError.noTabsFound
        }

        if !failures.isEmpty {
            throw RestorePartialFailure(totalRestored: totalRestored, failedBrowsers: failures)
        }

        return totalRestored
    }
}
