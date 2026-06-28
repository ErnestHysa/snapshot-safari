import SwiftUI

struct RestoreOptionsSheet: View {
    let title: String
    /// The browser(s) present in the snapshot. Used to determine the default.
    let sourceBrowsers: [Browser]
    let onRestore: (SnapshotService.RestoreMode, Browser?) -> Void

    @State private var selectedMode: SnapshotService.RestoreMode = .newWindow
    @State private var selectedBrowserChoice: BrowserChoice = .original
    @Environment(\.dismiss) private var dismiss

    /// All installed browsers that can receive tabs.
    private var installedBrowsers: [Browser] {
        Browser.installedBrowsers
    }

    /// Whether the currently selected browser supports window management.
    private var selectedBrowserSupportsWindowMode: Bool {
        switch selectedBrowserChoice {
        case .original:
            return true // Original browsers are always readable
        case .specific(let browser):
            return browser.supportsReadTabs
        }
    }

    init(
        title: String = "Restore Snapshot",
        sourceBrowsers: [Browser] = [],
        onRestore: @escaping (SnapshotService.RestoreMode, Browser?) -> Void
    ) {
        self.title = title
        self.sourceBrowsers = sourceBrowsers
        self.onRestore = onRestore
    }

    enum BrowserChoice: Hashable {
        case original
        case specific(Browser)

        var label: String {
            switch self {
            case .original: return "Original Browser(s)"
            case .specific(let browser): return browser.displayName
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.title2.bold())

            Text("Choose where and how to open these tabs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Restore mode picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Restore Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selectedBrowserSupportsWindowMode {
                    Picker("Restore mode", selection: $selectedMode) {
                        ForEach(SnapshotService.RestoreMode.allCases, id: \.self) { mode in
                            HStack {
                                Image(systemName: mode == .newWindow ? "macwindow.on.rectangle" : "macwindow")
                                    .font(.title3)
                                Text(mode.rawValue)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                } else {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("This browser doesn't support window management — tabs will open directly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            // Browser picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Target Browser")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Target browser", selection: $selectedBrowserChoice) {
                    Text("Original Browser(s)")
                        .tag(BrowserChoice.original)

                    Divider()

                    ForEach(installedBrowsers, id: \.rawValue) { browser in
                        HStack {
                            Image(systemName: browser.iconName)
                                .font(.title3)
                            Text(browser.displayName)
                        }
                        .tag(BrowserChoice.specific(browser))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .accessibilityLabel("Cancel restore")

                Button("Restore") {
                    let target: Browser?
                    switch selectedBrowserChoice {
                    case .original:
                        target = nil
                    case .specific(let browser):
                        target = browser
                    }
                    onRestore(selectedMode, target)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Restore tabs")
                .accessibilityHint("Opens the selected tabs using the chosen mode and browser.")
            }
        }
        .padding()
        .frame(width: 380)
    }
}
