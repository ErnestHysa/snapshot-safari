import SwiftUI
import SwiftData

@main
struct SnapshotSafariApp: App {
    let container: ModelContainer

    @State private var selectedTheme: AppTheme = .system
    @State private var updateChecker = SparkleUpdateChecker.shared
    @State private var syncService = SyncService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(selectedTheme.colorScheme)
                .onAppear {
                    loadTheme()
                    // Clean up old trash on launch
                    let context = container.mainContext
                    let service = SnapshotService(modelContext: context)
                    service.cleanUpOldTrash()
                }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    loadTheme()
                }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .modelContainer(container)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Take Snapshot") {
                    NotificationCenter.default.post(name: .takeSnapshot, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateChecker.checkForUpdates()
                }
                .disabled(!updateChecker.canCheckForUpdates)
            }
        }
    }

    init() {
        let schema = Schema([Snapshot.self, TabEntry.self])

        // Configure for CloudKit if the user has enabled it.
        let isCloudSyncEnabled = SyncService.shared.isSyncEnabled
        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        if isCloudSyncEnabled {
            let cloudConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .automatic
            )
            // Try the cloud config first; fall back to local if CloudKit isn't available.
            if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
                self.container = container
                SyncService.shared.isCloudAvailable = true
            } else {
                // CloudKit unavailable (not signed into iCloud, no container, etc.)
                self.container = (try? ModelContainer(for: schema, configurations: [localConfig]))
                    ?? Self.fallbackContainer
                SyncService.shared.isCloudAvailable = false
            }
        } else {
            self.container = (try? ModelContainer(for: schema, configurations: [localConfig]))
                ?? Self.fallbackContainer
        }
    }

    /// A last-resort in-memory container if local persistence also fails.
    private static var fallbackContainer: ModelContainer {
        let schema = Schema([Snapshot.self, TabEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    private func loadTheme() {
        let themeRaw = UserDefaults.standard.string(forKey: "appTheme") ?? "system"
        selectedTheme = AppTheme(rawValue: themeRaw) ?? .system
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let takeSnapshot = Notification.Name("takeSnapshot")
    static let openSettings = Notification.Name("openSettings")
}
