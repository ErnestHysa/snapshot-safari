import SwiftUI
import ServiceManagement

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @Bindable var autoSnapshotManager: AutoSnapshotManager
    @Bindable var permissionsService: PermissionsService
    @State private var syncService = SyncService.shared

    @State private var launchAtLogin = false
    @State private var selectedTheme: AppTheme = .system
    @State private var customIntervalText = ""
    @State private var showingCustomInterval = false
    @State private var sparkleChecker = SparkleUpdateChecker.shared
    @State private var showingSyncRestart = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView {
            generalTab
            autoSnapshotTab
            syncTab
            appearanceTab
            permissionsTab
            updatesTab
            aboutTab
        }
        .frame(width: 520, height: 500)
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

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Label("General", systemImage: "gearshape")
            }
        }
        .tabItem { Label("General", systemImage: "gearshape") }
        .padding()
    }

    // MARK: - Auto-Snapshots

    private var autoSnapshotTab: some View {
        Form {
            Section {
                Toggle("Enable auto-snapshots", isOn: $autoSnapshotManager.isEnabled)
                    .onChange(of: autoSnapshotManager.isEnabled) { _, _ in
                        toggleAutoSnapshots()
                    }
            } header: {
                Label("Auto-Snapshots", systemImage: "clock.arrow.circlepath")
            }

            if autoSnapshotManager.isEnabled {
                Section("Snapshot Interval") {
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
                }
            }
        }
        .tabItem { Label("Auto-Snapshots", systemImage: "clock.arrow.circlepath") }
        .padding()
    }

    // MARK: - iCloud Sync

    private var syncTab: some View {
        Form {
            Section {
                Toggle("Enable iCloud Sync", isOn: Binding(
                    get: { syncService.isSyncEnabled },
                    set: { newValue in
                        syncService.isSyncEnabled = newValue
                        showingSyncRestart = true
                    }
                ))
            } header: {
                Label("iCloud Sync", systemImage: "icloud")
            }

            Section {
                LabeledContent("Container", value: syncService.cloudKitContainerIdentifier)
                    .font(.caption)

                Text(syncService.syncStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Your snapshots will be synced across all your Macs signed into the same iCloud account. Requires iCloud to be enabled in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Note: Changes to iCloud sync require an app restart to take effect.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .tabItem { Label("Sync", systemImage: "icloud") }
        .padding()
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section {
                Picker("Theme", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Label("Appearance", systemImage: "paintpalette")
            }
        }
        .tabItem { Label("Appearance", systemImage: "paintpalette") }
        .padding()
    }

    // MARK: - Permissions

    private var permissionsTab: some View {
        Form {
            Section {
                HStack {
                    Label(permissionsService.statusMessage, systemImage: "lock.shield")
                    Spacer()
                    if permissionsService.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Button("Open Automation Settings") {
                    permissionsService.openAutomationSettings()
                }

                Button("Check Permission Again") {
                    Task {
                        await permissionsService.checkAutomationPermission()
                    }
                }
            } header: {
                Label("Permissions", systemImage: "lock.shield")
            }

            Section {
                Text("Snapshot Safari needs Automation access to Safari to read and restore your tabs. Your data never leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tabItem { Label("Permissions", systemImage: "lock.shield") }
        .padding()
    }

    // MARK: - Updates

    private var updatesTab: some View {
        Form {
            Section {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "1")

                Button {
                    sparkleChecker.checkForUpdates()
                } label: {
                    HStack {
                        Text("Check for Updates…")
                        Spacer()
                        if sparkleChecker.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(!sparkleChecker.canCheckForUpdates)
            } header: {
                Label("Updates", systemImage: "arrow.down.circle")
            }

            Section {
                Toggle("Check automatically", isOn: Binding(
                    get: { SparkleUpdater.shared.automaticallyChecksForUpdates },
                    set: { SparkleUpdater.shared.automaticallyChecksForUpdates = $0 }
                ))
                Toggle("Download automatically", isOn: Binding(
                    get: { SparkleUpdater.shared.automaticallyDownloadsUpdates },
                    set: { SparkleUpdater.shared.automaticallyDownloadsUpdates = $0 }
                ))
            }

            Section {
                Text("Snapshot Safari uses Sparkle to deliver updates. Your Mac will check for new versions when connected to the internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        .padding()
    }

    // MARK: - About

    private var aboutTab: some View {
        Form {
            Section {
                LabeledContent("Bundle ID", value: "com.ernest.snapshot-safari")
            } header: {
                Label("About", systemImage: "info.circle")
            }

            Section {
                Text("Built with ❤️ using SwiftUI, SwiftData, and Sparkle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link("Snapshot Safari on GitHub", destination: URL(string: "https://github.com/ernest/snapshot-safari")!)
                    .font(.caption)
            }
        }
        .tabItem { Label("About", systemImage: "info.circle") }
        .padding()
    }

    // MARK: - Helpers

    private var customIntervalLabel: String {
        if autoSnapshotManager.isCustomInterval {
            let minutes = Int(autoSnapshotManager.interval / 60)
            return "Custom (\(minutes) min)"
        }
        return "Custom…"
    }

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
                Button("Set") {
                    if let minutes = Double(customIntervalText), minutes >= 5 {
                        autoSnapshotManager.interval = minutes * 60
                        autoSnapshotManager.isCustomInterval = true
                        autoSnapshotManager.start()
                    }
                    showingCustomInterval = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
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
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }
}
