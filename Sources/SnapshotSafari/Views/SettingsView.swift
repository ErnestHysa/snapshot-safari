import SwiftUI
import ServiceManagement

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case autoSnapshots = "Auto-Snapshots"
    case sync = "iCloud Sync"
    case appearance = "Appearance"
    case permissions = "Permissions"
    case updates = "Updates"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .autoSnapshots: return "clock.arrow.circlepath"
        case .sync: return "icloud"
        case .appearance: return "paintpalette"
        case .permissions: return "lock.shield"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var autoSnapshotManager: AutoSnapshotManager
    @Bindable var permissionsService: PermissionsService
    @State private var syncService = SyncService.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var launchAtLogin = false
    @State private var selectedTheme: AppTheme = .system
    @State private var customIntervalText = ""
    @State private var showingCustomInterval = false
    @State private var sparkleChecker = SparkleUpdateChecker.shared
    @State private var showingSyncRestart = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: 720, height: 520)
        .background(.regularMaterial)
        .sheet(isPresented: $showingCustomInterval) {
            customIntervalSheet
        }
        .alert("Restart Required", isPresented: $showingSyncRestart) {
            Button("OK") {}
        } message: {
            Text("iCloud sync changes will take effect after you restart the app.")
        }
        .onAppear {
            loadSettings()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "camera.aperture")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("Snapshot Safari")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: 200)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Content Pane

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general: generalTab
        case .autoSnapshots: autoSnapshotTab
        case .sync: syncTab
        case .appearance: appearanceTab
        case .permissions: permissionsTab
        case .updates: updatesTab
        case .about: aboutTab
        }
    }

    // MARK: - General

    private var generalTab: some View {
        SettingsPane(title: SettingsTab.general.rawValue, subtitle: "App-wide behaviour") {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                    .accessibilityHint("Opens Snapshot Safari automatically when you log in to your Mac.")
            } header: {
                Label("Startup", systemImage: "power")
            } footer: {
                Text("Adds Snapshot Safari as a login item. Disable to remove.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Auto-Snapshots

    private var autoSnapshotTab: some View {
        SettingsPane(title: SettingsTab.autoSnapshots.rawValue, subtitle: "Capture tabs automatically on a schedule") {
            Section {
                Toggle("Enable auto-snapshots", isOn: $autoSnapshotManager.isEnabled)
                    .onChange(of: autoSnapshotManager.isEnabled) { _, _ in
                        toggleAutoSnapshots()
                    }
                    .accessibilityHint("When enabled, snapshots are automatically captured on a schedule.")

                if autoSnapshotManager.isEnabled {
                    Section {
                        Picker("Capture target", selection: $autoSnapshotManager.target) {
                            ForEach(AutoSnapshotTarget.all) { target in
                                Label(target.label, systemImage: target.icon).tag(target)
                            }
                        }
                        .accessibilityLabel("Auto-snapshot target")
                        .accessibilityHint("Choose which browser to auto-snapshot: the frontmost browser, all running browsers, Safari, or Chrome.")
                    } header: {
                        Label("Capture Target", systemImage: "target")
                    }

                    Section {
                        ForEach(AutoSnapshotManager.presets, id: \.label) { preset in
                            Button {
                                autoSnapshotManager.interval = preset.interval
                                autoSnapshotManager.isCustomInterval = false
                                autoSnapshotManager.start()
                            } label: {
                                HStack {
                                    Text(preset.label)
                                    Spacer()
                                    if !autoSnapshotManager.isCustomInterval
                                        && abs(autoSnapshotManager.interval - preset.interval) < 1 {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(preset.label) interval")
                            .accessibilityHint("Sets auto-snapshots to run every \(preset.label.lowercased()).")
                        }

                        Button {
                            showingCustomInterval = true
                        } label: {
                            HStack {
                                Text(customIntervalLabel)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if autoSnapshotManager.isCustomInterval {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Custom interval")
                        .accessibilityHint("Set a custom interval in minutes for auto-snapshots.")
                    } header: {
                        Label("Snapshot Interval", systemImage: "timer")
                    }
                }
            } header: {
                Label("Schedule", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    // MARK: - iCloud Sync

    private var syncTab: some View {
        SettingsPane(title: SettingsTab.sync.rawValue, subtitle: "Sync snapshots across your Macs via iCloud") {
            Section {
                Toggle("Enable iCloud Sync", isOn: Binding(
                    get: { syncService.isSyncEnabled },
                    set: { newValue in
                        syncService.isSyncEnabled = newValue
                        showingSyncRestart = true
                    }
                ))
                .disabled(!syncService.iCloudEntitled)
                .accessibilityHint(syncService.iCloudEntitled
                    ? "Syncs your snapshots across all Macs signed into the same iCloud account. Requires restart to take effect."
                    : "iCloud sync requires a developer build of Snapshot Safari. See the GitHub repository for build instructions.")
            } header: {
                Label("Sync", systemImage: "icloud")
            }

            if !syncService.iCloudEntitled {
                Section {
                    Label("iCloud sync is unavailable in the public build.", systemImage: "icloud.slash")
                        .font(.callout)
                    Text("The iCloud / CloudKit entitlements require an Apple Developer ID signature. This public release is signed ad-hoc so it can be downloaded and run without a developer account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Build with iCloud — see the project README",
                         destination: URL(string: "https://github.com/ErnestHysa/snapshot-safari#icloud-sync")!)
                        .font(.caption)
                } header: {
                    Label("Developer Build Required", systemImage: "hammer")
                }
            }

            Section {
                LabeledContent("Container", value: syncService.cloudKitContainerIdentifier)
                    .font(.caption)
                Text(syncService.syncStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Status", systemImage: "info.circle")
            }
        }
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        SettingsPane(title: SettingsTab.appearance.rawValue, subtitle: "Theme and visual preferences") {
            Section {
                Picker("Theme", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.rawValue, systemImage: theme.icon).tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel("App theme")
                .accessibilityHint("Choose between light, dark, or system appearance.")
            } header: {
                Label("Theme", systemImage: "paintpalette")
            }
        }
    }

    // MARK: - Permissions

    private var permissionsTab: some View {
        SettingsPane(title: SettingsTab.permissions.rawValue, subtitle: "Grant access to control your browsers") {
            Section {
                ForEach(Browser.allCases.filter { $0.isInstalled && $0.supportsReadTabs }, id: \.rawValue) { browser in
                    HStack {
                        Image(systemName: browser.iconName)
                            .frame(width: 20)
                        Text(browser.displayName)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(permissionsService.permissions[browser.rawValue] == true ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(permissionsService.permissions[browser.rawValue] == true ? "Granted" : "Needed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if Browser.allCases.filter({ $0.isInstalled && !$0.supportsReadTabs }).isEmpty == false {
                    Divider()

                    ForEach(Browser.allCases.filter { $0.isInstalled && !$0.supportsReadTabs }, id: \.rawValue) { browser in
                        HStack {
                            Image(systemName: browser.iconName)
                                .frame(width: 20)
                            Text(browser.displayName)
                            Spacer()
                            Text("Tab reading not supported")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if permissionsService.isChecking {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                }
            } header: {
                Label("Browser Permissions", systemImage: "keyboard")
            }

            Section {
                Button("Open Automation Settings") {
                    permissionsService.openAutomationSettings()
                }
                .accessibilityHint("Opens System Settings to the Automation privacy pane.")

                Button("Check Permissions Again") {
                    Task {
                        await permissionsService.checkAllPermissions()
                    }
                }
                .accessibilityHint("Re-checks whether Snapshot Safari has Automation access to your browsers.")
            } header: {
                Label("Actions", systemImage: "arrow.triangle.2.circlepath")
            } footer: {
                Text("Snapshot Safari needs Automation access to read and restore your browser tabs. Your data never leaves your Mac. Browsers need to be running for the permission check to work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Updates

    private var updatesTab: some View {
        SettingsPane(title: SettingsTab.updates.rawValue, subtitle: "Auto-update delivery via Sparkle") {
            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: appBuild)

                Button {
                    sparkleChecker.checkForUpdates()
                } label: {
                    HStack {
                        Text("Check for Updates…")
                        Spacer()
                        if sparkleChecker.isChecking {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(!sparkleChecker.canCheckForUpdates)
                .accessibilityHint("Checks if a newer version of Snapshot Safari is available.")
            } header: {
                Label("Updates", systemImage: "arrow.down.circle")
            }

            Section {
                Toggle("Check automatically", isOn: Binding(
                    get: { SparkleUpdater.shared.automaticallyChecksForUpdates },
                    set: { SparkleUpdater.shared.automaticallyChecksForUpdates = $0 }
                ))
                .accessibilityHint("When enabled, Snapshot Safari periodically checks for new versions in the background.")

                Toggle("Download automatically", isOn: Binding(
                    get: { SparkleUpdater.shared.automaticallyDownloadsUpdates },
                    set: { SparkleUpdater.shared.automaticallyDownloadsUpdates = $0 }
                ))
                .accessibilityHint("When enabled, updates are downloaded in the background and installed on next launch.")
            } header: {
                Label("Background", systemImage: "arrow.triangle.2.circlepath")
            } footer: {
                Text("Snapshot Safari uses Sparkle to deliver updates. Your Mac will check for new versions when connected to the internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        SettingsPane(title: SettingsTab.about.rawValue, subtitle: "Snapshot Safari") {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Snapshot Safari")
                            .font(.title2.bold())
                        Text("Save and restore your Safari tabs.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Bundle ID", value: "com.ernest.snapshot-safari")
            } header: {
                Label("Build", systemImage: "info.circle")
            }

            Section {
                Link("Snapshot Safari on GitHub",
                     destination: URL(string: "https://github.com/ErnestHysa/snapshot-safari")!)
                Link("Report an Issue",
                     destination: URL(string: "https://github.com/ErnestHysa/snapshot-safari/issues")!)
            } header: {
                Label("Resources", systemImage: "link")
            }
        }
    }

    // MARK: - Custom Interval Sheet

    private var customIntervalSheet: some View {
        VStack(spacing: 16) {
            Text("Custom Interval")
                .font(.headline)

            TextField("Minutes", text: $customIntervalText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .labelsHidden()

            Text("Enter the interval in minutes (minimum 5).")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingCustomInterval = false
                }
                .accessibilityLabel("Cancel custom interval")

                Button("Set") {
                    if let minutes = Double(customIntervalText), minutes >= 5 {
                        autoSnapshotManager.interval = minutes * 60
                        autoSnapshotManager.isCustomInterval = true
                        autoSnapshotManager.start()
                    }
                    showingCustomInterval = false
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Set custom interval")
                .accessibilityHint("Applies the entered interval in minutes for auto-snapshots.")
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Helpers

    private var customIntervalLabel: String {
        if autoSnapshotManager.isCustomInterval {
            let minutes = Int(autoSnapshotManager.interval / 60)
            return "Custom (\(minutes) min)"
        }
        return "Custom…"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private func loadSettings() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let themeRaw = UserDefaults.standard.string(forKey: "appTheme") ?? "system"
        selectedTheme = AppTheme(rawValue: themeRaw) ?? .system
    }

    private func toggleAutoSnapshots() {
        if autoSnapshotManager.isEnabled {
            autoSnapshotManager.start()
        } else {
            autoSnapshotManager.stop()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }
}

// MARK: - Reusable Pane

/// Visual wrapper for a settings tab's content. Standardises the
/// `.ultraThinMaterial` background, title, subtitle, and section spacing
/// across every tab so the panel reads as one coherent design rather than
/// seven independent forms.
struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.bold())
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.regularMaterial)
    }
}

// MARK: - Window Host

/// Hosts `SettingsView` in an `NSWindow` so the user gets native macOS window
/// chrome — traffic-light buttons, draggable titlebar, ⌘W to close.
/// `.sheet` on macOS doesn't provide this chrome by default.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(
        autoSnapshotManager: AutoSnapshotManager,
        permissionsService: PermissionsService
    ) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView(
                autoSnapshotManager: autoSnapshotManager,
                permissionsService: permissionsService
            )
        )

        let win = NSWindow(contentViewController: hosting)
        win.title = "Snapshot Safari Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 720, height: 520))
        win.center()
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
    }
}