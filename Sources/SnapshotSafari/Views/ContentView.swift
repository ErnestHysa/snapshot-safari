import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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
                        takeSnapshotButton(with: viewModel)
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
                ProgressView("Working with Safari\u{2026}")
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear {
            initializeServices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .takeSnapshot)) { _ in
            guard !isTakingSnapshot else { return }
            isTakingSnapshot = true
            Task {
                await viewModel?.takeSnapshot()
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

    private func takeSnapshotButton(with viewModel: SnapshotListViewModel) -> some View {
        Button(action: { takeSnapshot(viewModel) }) {
            Image(systemName: "camera.fill")
        }
        .disabled(isTakingSnapshot)
        .help("Take Snapshot")
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("Take a new snapshot")
        .accessibilityHint("Captures all open Safari tabs and saves them as a new snapshot.")
    }

    // MARK: - Actions

    private func takeSnapshot(_ viewModel: SnapshotListViewModel) {
        guard !isTakingSnapshot else { return }
        isTakingSnapshot = true
        Task {
            await viewModel.takeSnapshot()
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
        viewModel = SnapshotListViewModel(snapshotService: service)
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
            await permissionsService.checkAutomationPermission()
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
