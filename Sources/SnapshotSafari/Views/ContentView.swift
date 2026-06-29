import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @State private var viewModel: SnapshotListViewModel?
    @State private var autoSnapshotManager: AutoSnapshotManager?
    @State private var permissionsService = PermissionsService()
    @State private var showingWelcome = false
    @State private var showingTrash = false
    @State private var isTakingSnapshot = false

    var body: some View {
        Group {
            if let viewModel, let autoSnapshotManager {
                NavigationSplitView {
                    sidebar(viewModel: viewModel)
                } detail: {
                    if let snapshot = viewModel.selectedSnapshot {
                        SnapshotDetailView(
                            snapshot: snapshot,
                            viewModel: viewModel
                        )
                    } else {
                        emptyState
                    }
                }
                .toolbar {
                    ToolbarItem {
                        TrashButton(count: viewModel.trashedSnapshots.count) {
                            showingTrash = true
                        }
                        .disabled(viewModel.trashedSnapshots.isEmpty)
                        .opacity(viewModel.trashedSnapshots.isEmpty ? 0.4 : 1.0)
                        .accessibilityLabel("Show recently deleted snapshots")
                    }
                    ToolbarItem {
                        importButton(with: viewModel)
                    }
                    ToolbarItem {
                        exportMenu(with: viewModel)
                    }
                    ToolbarItem {
                        settingsButton(autoSnapshotManager: autoSnapshotManager)
                    }
                    ToolbarItem {
                        captureMenu(with: viewModel)
                    }
                }
                .sheet(isPresented: $showingWelcome) {
                    WelcomeView(permissionsService: permissionsService)
                }
                .sheet(isPresented: $showingTrash) {
                    TrashView(viewModel: viewModel)
                }
                .sheet(isPresented: comparisonBinding(for: viewModel)) {
                    if let diff = viewModel.snapshotDiff {
                        CompareSnapshotsView(diff: diff)
                    }
                }
                .onAppear {
                    checkFirstLaunch()
                }
                .alert(
                    viewModel.showError ? "Error" : "Restore Complete",
                    isPresented: alertBinding(for: viewModel)
                ) {
                    Button("OK") {
                        viewModel.showError = false
                        viewModel.showInfo = false
                    }
                } message: {
                    Text(viewModel.showError
                        ? (viewModel.errorMessage ?? "An unknown error occurred.")
                        : (viewModel.infoMessage ?? ""))
                }
            } else {
                ProgressView("Loading\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            if isTakingSnapshot || (viewModel?.isLoading ?? false) {
                ProgressView("Capturing tabs\u{2026}")
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear {
            initializeServices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .takeSnapshot)) { _ in
            guard !isTakingSnapshot, let vm = viewModel else { return }
            isTakingSnapshot = true
            Task {
                await vm.takeSnapshotOfFrontmostBrowser()
                isTakingSnapshot = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            if let autoSnapshotManager {
                SettingsWindow.show(
                    autoSnapshotManager: autoSnapshotManager,
                    permissionsService: permissionsService
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importSnapshots)) { _ in
            viewModel?.importSnapshotsFromFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSnapshot)) { _ in
            if let snapshot = viewModel?.selectedSnapshot {
                viewModel?.exportSnapshot(snapshot)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportAllSnapshots)) { _ in
            viewModel?.exportAllSnapshots()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedSnapshot)) { _ in
            if let snapshot = viewModel?.selectedSnapshot {
                viewModel?.deleteSnapshot(snapshot)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .undoLastDelete)) { _ in
            viewModel?.undoLastDelete()
        }
        .onReceive(NotificationCenter.default.publisher(for: .restoreFromTrash)) { _ in
            guard let vm = viewModel, !vm.trashedSnapshots.isEmpty else { return }
            vm.restoreAllFromTrash()
        }
        .onReceive(NotificationCenter.default.publisher(for: .takeSnapshotBrowser)) { notification in
            guard !isTakingSnapshot, let vm = viewModel else { return }
            guard let raw = notification.object as? String,
                  let browser = Browser(rawValue: raw) else { return }
            isTakingSnapshot = true
            Task {
                await vm.takeSnapshotOfBrowser(browser)
                isTakingSnapshot = false
            }
        }
    }

    // MARK: - Toolbar Sub-views

    private func settingsButton(autoSnapshotManager: AutoSnapshotManager) -> some View {
        Button(action: {
            SettingsWindow.show(
                autoSnapshotManager: autoSnapshotManager,
                permissionsService: permissionsService
            )
        }) {
            Image(systemName: "gearshape")
        }
        .help("Settings")
        .accessibilityLabel("Open settings")
        .accessibilityHint("Opens the settings window with tabs for general, auto-snapshots, sync, appearance, permissions, updates, and about.")
    }

    private func captureMenu(with viewModel: SnapshotListViewModel) -> some View {
        Menu {
            // Primary action: frontmost browser via hotkey
            Button {
                takeSnapshotOfFrontmost(viewModel)
            } label: {
                if let frontmost = Browser.frontmostBrowser {
                    Label("Capture \(frontmost.displayName)", systemImage: frontmost.iconName)
                } else {
                    Label("Capture Active Browser", systemImage: "camera.fill")
                }
            }
            .disabled(isTakingSnapshot)

            Divider()

            // Individual browser buttons (only installed & readable)
            ForEach(Browser.allCases.filter { $0.isInstalled && $0.supportsReadTabs }, id: \.rawValue) { browser in
                Button {
                    takeSnapshotOf(viewModel, browser: browser)
                } label: {
                    Label("Capture \(browser.displayName)", systemImage: browser.iconName)
                }
                .disabled(isTakingSnapshot || !browser.isRunning)
            }

            Divider()

            // Capture all running browsers
            Button {
                takeSnapshotOfAll(viewModel)
            } label: {
                Label("Capture All Running", systemImage: "square.grid.2x2")
            }
            .disabled(isTakingSnapshot || Browser.readableRunningBrowsers.isEmpty)
            .keyboardShortcut("n", modifiers: [.command, .shift])
        } label: {
            Image(systemName: "camera.fill")
        }
        .help("Take Snapshot")
        .accessibilityLabel("Take a new snapshot")
        .accessibilityHint("Capture open tabs from a browser. ⌘N captures the frontmost browser, ⌘⇧N captures all running browsers.")
    }

    // MARK: - Actions

    private func takeSnapshotOfFrontmost(_ viewModel: SnapshotListViewModel) {
        guard !isTakingSnapshot else { return }
        isTakingSnapshot = true
        Task {
            await viewModel.takeSnapshotOfFrontmostBrowser()
            isTakingSnapshot = false
        }
    }

    private func takeSnapshotOf(_ viewModel: SnapshotListViewModel, browser: Browser) {
        guard !isTakingSnapshot else { return }
        isTakingSnapshot = true
        Task {
            await viewModel.takeSnapshotOfBrowser(browser)
            isTakingSnapshot = false
        }
    }

    private func takeSnapshotOfAll(_ viewModel: SnapshotListViewModel) {
        guard !isTakingSnapshot else { return }
        isTakingSnapshot = true
        Task {
            await viewModel.takeSnapshotOfAllBrowsers()
            isTakingSnapshot = false
        }
    }

    // MARK: - Bindings

    private func comparisonBinding(for viewModel: SnapshotListViewModel) -> Binding<Bool> {
        Binding(
            get: { viewModel.showComparison },
            set: { viewModel.showComparison = $0 }
        )
    }

    private func alertBinding(for viewModel: SnapshotListViewModel) -> Binding<Bool> {
        Binding(
            get: { viewModel.showError || viewModel.showInfo },
            set: { newValue in
                if !newValue {
                    viewModel.showError = false
                    viewModel.showInfo = false
                }
            }
        )
    }

    // MARK: - Sidebar

    private func sidebar(viewModel: SnapshotListViewModel) -> some View {
        SnapshotListView(viewModel: viewModel)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Snapshot Selected",
            systemImage: "photo.on.rectangle",
            description: Text("Select a snapshot from the sidebar or take a new one.")
        )
    }

    // MARK: - Lifecycle

    private func initializeServices() {
        guard viewModel == nil else { return }
        let service = SnapshotService(modelContext: modelContext)
        let vm = SnapshotListViewModel(snapshotService: service)
        vm.undoManager = undoManager
        viewModel = vm
        autoSnapshotManager = AutoSnapshotManager(snapshotService: service)
    }

    private func importButton(with viewModel: SnapshotListViewModel) -> some View {
        Button(action: { viewModel.importSnapshotsFromFile() }) {
            Image(systemName: "square.and.arrow.down")
        }
        .help("Import Snapshots")
        .keyboardShortcut("i", modifiers: .command)
        .accessibilityLabel("Import snapshots from a file")
        .accessibilityHint("Opens a file dialog to choose a Snapshot Safari export JSON file to import.")
    }

    private func exportMenu(with viewModel: SnapshotListViewModel) -> some View {
        Menu {
            Button("Export Selected…") {
                if let snapshot = viewModel.selectedSnapshot {
                    viewModel.exportSnapshot(snapshot)
                }
            }
            .disabled(viewModel.selectedSnapshot == nil)

            Button("Export All…") {
                viewModel.exportAllSnapshots()
            }
            .disabled(viewModel.snapshots.isEmpty)
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .help("Export Snapshots")
        .accessibilityLabel("Export snapshots")
        .accessibilityHint("Choose to export the selected snapshot or all snapshots to a JSON file.")
    }

    private func checkFirstLaunch() {
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunched {
            showingWelcome = true
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }

        Task {
            await permissionsService.checkAllPermissions()
        }
    }
}

// MARK: - Trash Button

private struct TrashButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash.fill")
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
        }
        .help("Recently Deleted (\(count))")
        .accessibilityLabel("Recently deleted snapshots")
        .accessibilityHint("Opens the trash view with \(count) deleted snapshots that can be restored.")
    }
}
