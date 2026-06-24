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

                Button("Import Snapshots…") {
                    NotificationCenter.default.post(name: .importSnapshots, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Export Selected…") {
                    NotificationCenter.default.post(name: .exportSnapshot, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Export All…") {
                    NotificationCenter.default.post(name: .exportAllSnapshots, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .pasteboard) {
                Button("Delete Snapshot") {
                    NotificationCenter.default.post(name: .deleteSelectedSnapshot, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
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

        // Configure for CloudKit only when the user has enabled sync AND this build
        // carries the iCloud entitlements required by AMFI. Public ad-hoc-signed
        // builds do not, so they always use the local store.
        let isCloudSyncEnabled = SyncService.shared.isSyncEnabled
        let hasICloudEntitlements = SyncService.shared.iCloudEntitled
        let useCloud = isCloudSyncEnabled && hasICloudEntitlements

        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        if useCloud {
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
            SyncService.shared.isCloudAvailable = false
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
    static let importSnapshots = Notification.Name("importSnapshots")
    static let exportSnapshot = Notification.Name("exportSnapshot")
    static let exportAllSnapshots = Notification.Name("exportAllSnapshots")
    static let deleteSelectedSnapshot = Notification.Name("deleteSelectedSnapshot")
    static let renameSelectedSnapshot = Notification.Name("renameSelectedSnapshot")
    static let compareSelectedSnapshot = Notification.Name("compareSelectedSnapshot")
}
