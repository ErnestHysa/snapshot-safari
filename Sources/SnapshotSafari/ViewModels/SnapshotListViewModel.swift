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

    // MARK: - Export / Import

    /// Export the selected snapshot to JSON and present a save dialog.
    func exportSnapshot(_ snapshot: Snapshot) {
        do {
            let data = try snapshotService.exportSnapshotToJSON(snapshot)
            try presentSaveDialog(data: data, defaultName: sanitizedFileName(snapshot.name))
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Export all non-trashed snapshots to JSON.
    func exportAllSnapshots() {
        do {
            let data = try snapshotService.exportMultipleSnapshotsToJSON(snapshots)
            try presentSaveDialog(data: data, defaultName: "All Snapshots")
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Present a file import dialog and import the selected JSON file.
    func importSnapshotsFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Snapshot Safari export file to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let count = try snapshotService.importSnapshots(from: data)
            refresh()
            errorMessage = "Imported \(count) snapshot\(count == 1 ? "" : "s") successfully."
            showError = true
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Present a save dialog and write the data to disk.
    private func presentSaveDialog(data: Data, defaultName: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(defaultName).json"
        panel.message = "Choose where to save the snapshot export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        try data.write(to: url)
    }

    /// Create a safe file name from the snapshot name.
    private func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        return String(name.unicodeScalars.filter { allowed.contains($0) }).trimmingCharacters(in: .whitespaces)
    }
}
