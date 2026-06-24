import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
final class SnapshotListViewModel {
    var searchText = ""
    var snapshots: [Snapshot] = []
    var selectedSnapshot: Snapshot?
    var isLoading = false
    var errorMessage: String?
    var showError = false

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

    func deleteSnapshot(_ snapshot: Snapshot) {
        snapshotService.deleteSnapshot(snapshot)
        withAnimation {
            snapshots.removeAll { $0.id == snapshot.id }
            if selectedSnapshot?.id == snapshot.id {
                selectedSnapshot = snapshots.first
            }
        }
    }

    func renameSnapshot(_ snapshot: Snapshot, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        snapshotService.renameSnapshot(snapshot, to: newName)
    }

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
}
