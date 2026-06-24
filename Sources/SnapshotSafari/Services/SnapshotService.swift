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

    func fetchAllSnapshots() -> [Snapshot] {
        let descriptor = FetchDescriptor<Snapshot>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func searchSnapshots(query: String) -> [Snapshot] {
        guard !query.isEmpty else { return fetchAllSnapshots() }

        let lowercased = query.lowercased()

        let descriptor = FetchDescriptor<Snapshot>(
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

    // MARK: - Update

    func renameSnapshot(_ snapshot: Snapshot, to newName: String) {
        snapshot.name = newName
        snapshot.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Delete

    func deleteSnapshot(_ snapshot: Snapshot) {
        modelContext.delete(snapshot)
        try? modelContext.save()
    }

    func deleteSnapshots(_ snapshots: [Snapshot]) {
        for snapshot in snapshots {
            modelContext.delete(snapshot)
        }
        try? modelContext.save()
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
