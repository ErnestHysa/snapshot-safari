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
        let config: ModelConfiguration

        if isCloudSyncEnabled {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .automatic
            )
        } else {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
        }

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
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
