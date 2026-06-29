import Foundation
import SwiftUI
import SwiftData
import AppKit

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
    var infoMessage: String?
    var showInfo = false

    /// Undo manager for delete/restore operations. Set by the hosting view.
    var undoManager: UndoManager?

    /// Tracks the most recently deleted snapshot ID for the explicit menu command.
    private var lastDeletedSnapshotID: UUID?

    /// Filter snapshots by browser origin.
    var browserFilter: BrowserFilter = .all

    enum BrowserFilter: Hashable {
        case all
        case captureAll
        case specific(Browser)

        var label: String {
            switch self {
            case .all: return "All Snapshots"
            case .captureAll: return "Capture All"
            case .specific(let browser): return browser.shortName
            }
        }

        var iconName: String {
            switch self {
            case .all: return "tray.full"
            case .captureAll: return "square.grid.2x2"
            case .specific(let browser): return browser.iconName
            }
        }
    }

    /// The set of browsers that appear in at least one snapshot (for populating the filter menu).
    var availableBrowserFilters: [BrowserFilter] {
        var filters: [BrowserFilter] = [.all]
        let browserIds = Set(snapshots.flatMap { $0.tabs.map(\.browserId) })
        let browsers = browserIds.compactMap { Browser(rawValue: $0) }.sorted { $0.displayName < $1.displayName }
        if browsers.count > 1 {
            filters.append(.captureAll)
        }
        for browser in browsers {
            filters.append(.specific(browser))
        }
        return filters
    }

    private let snapshotService: SnapshotService

    var filteredSnapshots: [Snapshot] {
        let base = browserFilteredSnapshots
        guard !searchText.isEmpty else { return base }
        let query = searchText.lowercased()
        return base.filter { snapshot in
            snapshot.name.localizedCaseInsensitiveContains(query)
            || snapshot.tabs.contains { tab in
                tab.title.localizedCaseInsensitiveContains(query)
                || tab.url.localizedCaseInsensitiveContains(query)
                || tab.domain.localizedCaseInsensitiveContains(query)
            }
        }
    }

    /// Apply browser-only filtering (text search applies on top of this).
    private var browserFilteredSnapshots: [Snapshot] {
        switch browserFilter {
        case .all:
            return snapshots
        case .captureAll:
            return snapshots.filter { isMultiBrowserSnapshot($0) }
        case .specific(let browser):
            return snapshots.filter { snapshot in
                snapshot.tabs.contains { $0.browserId == browser.rawValue }
            }
        }
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

        do {
            let snapshot = try await snapshotService.takeSnapshot(isAuto: isAuto)
            isLoading = false
            withAnimation {
                snapshots.insert(snapshot, at: 0)
                selectedSnapshot = snapshot
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Capture the frontmost browser (hotkey path).
    /// When the frontmost app is SnapshotSafari itself (e.g. user clicks
    /// File → Take Snapshot from the menu bar), falls back to the first
    /// readable running browser so the user still gets a snapshot.
    func takeSnapshotOfFrontmostBrowser(isAuto: Bool = false) async {
        let browserToCapture: Browser
        if let frontmost = Browser.frontmostBrowser, frontmost.supportsReadTabs {
            browserToCapture = frontmost
        } else if let fallback = Browser.readableRunningBrowsers.first {
            browserToCapture = fallback
        } else {
            errorMessage = "No supported browser is currently running."
            showError = true
            return
        }

        isLoading = true

        do {
            let snapshot = try await snapshotService.takeSnapshot(browser: browserToCapture, isAuto: isAuto)
            isLoading = false
            withAnimation {
                snapshots.insert(snapshot, at: 0)
                selectedSnapshot = snapshot
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Capture a specific browser
    func takeSnapshotOfBrowser(_ browser: Browser, isAuto: Bool = false) async {
        isLoading = true

        do {
            let snapshot = try await snapshotService.takeSnapshot(browser: browser, isAuto: isAuto)
            isLoading = false
            withAnimation {
                snapshots.insert(snapshot, at: 0)
                selectedSnapshot = snapshot
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Capture ALL running browsers with tab-reading support
    func takeSnapshotOfAllBrowsers(isAuto: Bool = false) async {
        isLoading = true

        do {
            let snapshot = try await snapshotService.takeSnapshotOfAllBrowsers(isAuto: isAuto)
            isLoading = false
            withAnimation {
                snapshots.insert(snapshot, at: 0)
                selectedSnapshot = snapshot
            }
        } catch let partial as SnapshotService.CapturePartialFailure {
            isLoading = false
            withAnimation {
                snapshots.insert(partial.snapshot, at: 0)
                selectedSnapshot = partial.snapshot
            }
            infoMessage = partial.localizedDescription
            showInfo = true
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Trash / Delete

    func deleteSnapshot(_ snapshot: Snapshot) {
        snapshotService.trashSnapshot(snapshot)

        // Register undo action so Cmd+Z can restore
        registerUndoDelete(snapshot)

        withAnimation {
            snapshots.removeAll { $0.id == snapshot.id }
            trashedSnapshots = snapshotService.fetchTrashedSnapshots()
            if selectedSnapshot?.id == snapshot.id {
                selectedSnapshot = snapshots.first
            }
        }
    }

    /// Undo the most recent deletion (triggered by Cmd+Z via UndoManager).
    func undoLastDelete() {
        guard let id = lastDeletedSnapshotID else { return }
        let trashed = snapshotService.fetchTrashedSnapshots()
        if let snapshot = trashed.first(where: { $0.id == id }) {
            restoreFromTrash(snapshot)
            lastDeletedSnapshotID = nil
        }
    }

    private func registerUndoDelete(_ snapshot: Snapshot) {
        let snapshotID = snapshot.id
        lastDeletedSnapshotID = snapshotID

        // Capture the snapshot ID directly in the closure so each undo
        // action restores its own snapshot — not just the most recent one.
        undoManager?.registerUndo(withTarget: self) { target in
            let trashed = target.snapshotService.fetchTrashedSnapshots()
            if let s = trashed.first(where: { $0.id == snapshotID }) {
                target.restoreFromTrash(s)
            }
        }
        undoManager?.setActionName("Delete Snapshot")
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

    func restoreSnapshot(_ snapshot: Snapshot, mode: SnapshotService.RestoreMode, targetBrowser: Browser? = nil) async {
        isLoading = true

        do {
            let restoredCount = try await snapshotService.restoreSnapshot(snapshot, mode: mode, targetBrowser: targetBrowser)
            isLoading = false
            // Activate handled inside SnapshotService now
            infoMessage = "Successfully restored \(restoredCount) tab\(restoredCount == 1 ? "" : "s")."
            showInfo = true
        } catch let partial as SnapshotService.RestorePartialFailure {
            isLoading = false
            infoMessage = partial.localizedDescription
            showInfo = true
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func restoreTabs(_ entries: [TabEntry], mode: SnapshotService.RestoreMode, targetBrowser: Browser? = nil) async {
        isLoading = true

        do {
            let restoredCount = try await snapshotService.restoreTabs(entries, mode: mode, targetBrowser: targetBrowser)
            isLoading = false
            infoMessage = "Successfully restored \(restoredCount) tab\(restoredCount == 1 ? "" : "s")."
            showInfo = true
        } catch let partial as SnapshotService.RestorePartialFailure {
            isLoading = false
            infoMessage = partial.localizedDescription
            showInfo = true
        } catch {
            isLoading = false
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

    /// The set of unique browser bundle IDs present in the snapshot's tabs.
    func browsersInSnapshot(_ snapshot: Snapshot) -> [Browser] {
        let ids = Set(snapshot.tabs.map { $0.browserId })
        return ids.compactMap { Browser(rawValue: $0) }.sorted { $0.displayName < $1.displayName }
    }

    /// Whether a snapshot has tabs from multiple browsers.
    func isMultiBrowserSnapshot(_ snapshot: Snapshot) -> Bool {
        browsersInSnapshot(snapshot).count > 1
    }
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
