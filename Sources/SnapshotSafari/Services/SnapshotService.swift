import Foundation
import SwiftData

@MainActor
final class SnapshotService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create

    /// Takes a new snapshot of all open Safari tabs
    @discardableResult
    func takeSnapshot(isAuto: Bool = false) async throws -> Snapshot {
        let bridge = SafariBridge()
        let tabs = try await bridge.readAllTabs()

        guard !tabs.isEmpty else {
            throw SafariBridgeError.noTabsFound
        }

        let tabEntries = tabs.map { tab in
            TabEntry(
                url: tab.url,
                title: tab.title,
                windowIndex: tab.windowIndex,
                index: tab.index
            )
        }

        let name = AutoNamer.generateName(tabCount: tabEntries.count, isAuto: isAuto)
        let snapshot = Snapshot(name: name, tabs: tabEntries, isAutoSnapshot: isAuto)

        modelContext.insert(snapshot)
        try modelContext.save()

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

    // MARK: - Legacy Delete (for backward compat - delegates to trash)

    func deleteSnapshot(_ snapshot: Snapshot) {
        trashSnapshot(snapshot)
    }

    func deleteSnapshots(_ snapshots: [Snapshot]) {
        trashSnapshots(snapshots)
    }

    // MARK: - Restore

    enum RestoreMode: String, CaseIterable {
        case newWindow = "New Safari Window"
        case currentWindow = "Current Window"

        var bridgeMode: SafariBridge.RestoreMode {
            switch self {
            case .newWindow: return .newWindow
            case .currentWindow: return .currentWindow
            }
        }
    }

    func restoreSnapshot(_ snapshot: Snapshot, mode: RestoreMode) async throws {
        let bridge = SafariBridge()
        let tabs = snapshot.tabs.map { entry in
            SafariTab(
                url: entry.url,
                title: entry.title,
                windowIndex: entry.windowIndex,
                index: entry.index
            )
        }
        try await bridge.restoreTabs(tabs, mode: mode.bridgeMode)
    }

    func restoreTabs(_ entries: [TabEntry], mode: RestoreMode) async throws {
        let bridge = SafariBridge()
        let tabs = entries.map { entry in
            SafariTab(
                url: entry.url,
                title: entry.title,
                windowIndex: entry.windowIndex,
                index: entry.index
            )
        }
        try await bridge.restoreTabs(tabs, mode: mode.bridgeMode)
    }
}
