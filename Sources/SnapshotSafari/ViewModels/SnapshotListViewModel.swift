import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
final class SnapshotListViewModel {
    var searchText = ""
    var snapshots: [Snapshot] = []
    var trashedSnapshots: [Snapshot] = []
    var selectedSnapshot: Snapshot?
    var isLoading = false
    var errorMessage: String?
    var showError = false
    var showingTrash = false
    var snapshotDiff: SnapshotDiff?
    var showComparison = false

    private let snapshotService: SnapshotService

    var filteredSnapshots: [Snapshot] {
        guard !searchText.isEmpty else { return snapshots }
        return snapshotService.searchSnapshots(query: searchText)
    }

    init(snapshotService: SnapshotService) {
        self.snapshotService = snapshotService
        refresh()
    }

    func refresh() {
        snapshots = snapshotService.fetchAllSnapshots()
        trashedSnapshots = snapshotService.fetchTrashedSnapshots()
    }

    func takeSnapshot(isAuto: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await snapshotService.takeSnapshot(isAuto: isAuto)
            withAnimation {
                snapshots.insert(snapshot, at: 0)
                selectedSnapshot = snapshot
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Trash / Delete

    func deleteSnapshot(_ snapshot: Snapshot) {
        snapshotService.trashSnapshot(snapshot)
        withAnimation {
            snapshots.removeAll { $0.id == snapshot.id }
            trashedSnapshots = snapshotService.fetchTrashedSnapshots()
            if selectedSnapshot?.id == snapshot.id {
                selectedSnapshot = snapshots.first
            }
        }
    }

    func restoreFromTrash(_ snapshot: Snapshot) {
        snapshotService.restoreFromTrash(snapshot)
        withAnimation {
            trashedSnapshots.removeAll { $0.id == snapshot.id }
            snapshots = snapshotService.fetchAllSnapshots()
        }
    }

    func restoreAllFromTrash() {
        snapshotService.restoreAllFromTrash()
        withAnimation {
            trashedSnapshots = []
            snapshots = snapshotService.fetchAllSnapshots()
        }
    }

    func permanentlyDelete(_ snapshot: Snapshot) {
        snapshotService.permanentlyDelete(snapshot)
        withAnimation {
            trashedSnapshots.removeAll { $0.id == snapshot.id }
        }
    }

    func emptyTrash() {
        snapshotService.permanentlyDeleteAllTrashed()
        withAnimation {
            trashedSnapshots = []
        }
    }

    // MARK: - Rename

    func renameSnapshot(_ snapshot: Snapshot, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        snapshotService.renameSnapshot(snapshot, to: newName)
    }

    // MARK: - Restore

    func restoreSnapshot(_ snapshot: Snapshot, mode: SnapshotService.RestoreMode) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await snapshotService.restoreSnapshot(snapshot, mode: mode)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func restoreTabs(_ entries: [TabEntry], mode: SnapshotService.RestoreMode) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await snapshotService.restoreTabs(entries, mode: mode)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Comparison

    func compareSnapshots(_ older: Snapshot, _ newer: Snapshot) {
        snapshotDiff = snapshotService.compareSnapshots(older, newer)
        showComparison = true
    }
}
