import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SnapshotListViewModel?
    @State private var autoSnapshotManager: AutoSnapshotManager?
    @State private var permissionsService = PermissionsService()
    @State private var showingSettings = false
    @State private var showingWelcome = false

    var body: some View {
        Group {
            if let viewModel, let autoSnapshotManager {
                NavigationSplitView {
                    SnapshotListView(viewModel: viewModel)
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
                    ToolbarItemGroup {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                        .help("Settings")

                        Button(action: {
                            Task { await viewModel.takeSnapshot() }
                        }) {
                            Image(systemName: "camera.fill")
                        }
                        .help("Take Snapshot")
                        .keyboardShortcut("n", modifiers: .command)
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(
                        autoSnapshotManager: autoSnapshotManager,
                        permissionsService: permissionsService
                    )
                }
                .sheet(isPresented: $showingWelcome) {
                    WelcomeView(permissionsService: permissionsService)
                }
                .onAppear {
                    checkFirstLaunch()
                }
                .alert("Error", isPresented: Binding(
                    get: { viewModel.showError },
                    set: { viewModel.showError = $0 }
                )) {
                    Button("OK") {}
                } message: {
                    Text(viewModel.errorMessage ?? "An unknown error occurred.")
                }
                .overlay {
                    if viewModel.isLoading {
                        ProgressView("Working with Safari…")
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            initializeServices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .takeSnapshot)) { _ in
            Task { await viewModel?.takeSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showingSettings = true
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Snapshot Selected",
            systemImage: "photo.on.rectangle",
            description: Text("Select a snapshot from the sidebar or take a new one.")
        )
    }

    private func initializeServices() {
        guard viewModel == nil else { return }
        let service = SnapshotService(modelContext: modelContext)
        viewModel = SnapshotListViewModel(snapshotService: service)
        autoSnapshotManager = AutoSnapshotManager(snapshotService: service)
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
