import SwiftUI

struct SnapshotDetailView: View {
    @Bindable var snapshot: Snapshot
    let viewModel: SnapshotListViewModel

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showingRestoreAllOptions = false
    @State private var showingSelectedRestoreOptions = false
    @State private var selectedTabs: Set<UUID> = []
    @State private var searchText = ""

    /// Unique browsers in this snapshot (cached for badge rendering).
    private var browsers: [Browser] {
        viewModel.browsersInSnapshot(snapshot)
    }

    private var isMultiBrowser: Bool {
        viewModel.isMultiBrowserSnapshot(snapshot)
    }

    var filteredTabs: [TabEntry] {
        guard !searchText.isEmpty else { return snapshot.tabs }
        let query = searchText.lowercased()
        return snapshot.tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(query)
            || tab.url.localizedCaseInsensitiveContains(query)
            || tab.domain.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                if isEditingName {
                    TextField("Snapshot name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2.bold())
                        .onSubmit {
                            viewModel.renameSnapshot(snapshot, to: editedName)
                            isEditingName = false
                        }
                } else {
                    HStack {
                        Text(snapshot.name)
                            .font(.title2.bold())
                            .accessibilityLabel("Snapshot name: \(snapshot.name)")
                        Button {
                            editedName = snapshot.name
                            isEditingName = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Rename")
                        .accessibilityLabel("Rename snapshot")
                        .accessibilityHint("Edit the name of this snapshot.")
                    }
                }

                if isMultiBrowser {
                    HStack(spacing: 4) {
                        Label("Capture All", systemImage: "square.grid.2x2")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.1))
                            .clipShape(Capsule())

                        ForEach(browsers, id: \.rawValue) { browser in
                            HStack(spacing: 3) {
                                Image(systemName: browser.iconName)
                                    .font(.system(size: 8))
                                Text(browser.shortName)
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(browser.brandColor.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(browser.brandColor)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Label(snapshot.formattedDate, systemImage: "calendar")
                        .accessibilityLabel("Created on \(snapshot.formattedDate)")
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Label("\(snapshot.tabCount) tab\(snapshot.tabCount == 1 ? "" : "s")", systemImage: "square.on.square")
                        .accessibilityLabel("\(snapshot.tabCount) tabs")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)

            Divider()

            // Tab list
            if snapshot.tabs.isEmpty {
                ContentUnavailableView(
                    "No Tabs",
                    systemImage: "square.on.square.dashed",
                    description: Text("This snapshot has no tabs.")
                )
            } else {
                VStack(spacing: 0) {
                    TextField("Search tabs…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                    Divider()

                    List(selection: $selectedTabs) {
                        ForEach(filteredTabs, id: \.id) { tab in
                            TabRow(tab: tab)
                                .tag(tab.id)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .alternatingRowBackgrounds()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Action bar
            HStack(spacing: 12) {
                Button {
                    showingRestoreAllOptions = true
                } label: {
                    Label("Restore All", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(snapshot.tabs.isEmpty)
                .accessibilityLabel("Restore all tabs")
                .accessibilityHint("Opens all tabs from this snapshot in Safari, choosing new or current window.")

                if !selectedTabs.isEmpty {
                    Button {
                        showingSelectedRestoreOptions = true
                    } label: {
                        Label("Restore Selected (\(selectedTabs.count))", systemImage: "arrow.up.doc")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Restore \(selectedTabs.count) selected tabs")
                }

                Button {
                    viewModel.exportSnapshot(snapshot)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Export Snapshot")
                .keyboardShortcut("e", modifiers: .command)
                .accessibilityLabel("Export this snapshot")
                .accessibilityHint("Saves this snapshot as a JSON file that can be imported later.")

                Spacer()

                Button(role: .destructive) {
                    viewModel.deleteSnapshot(snapshot)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .help("Delete Snapshot")
                .keyboardShortcut(.delete, modifiers: .command)
                .accessibilityLabel("Delete this snapshot")
                .accessibilityHint("Moves this snapshot to the trash. It can be restored later.")
            }
            .padding()
            .background(.ultraThinMaterial)
        }
.sheet(isPresented: $showingRestoreAllOptions) {
            RestoreOptionsSheet(
                sourceBrowsers: viewModel.browsersInSnapshot(snapshot),
                onRestore: { mode, targetBrowser in
                    Task {
                        await viewModel.restoreSnapshot(snapshot, mode: mode, targetBrowser: targetBrowser)
                    }
                }
            )
        }
        .sheet(isPresented: $showingSelectedRestoreOptions) {
            let entries = snapshot.tabs.filter { selectedTabs.contains($0.id) }
            let entryBrowsers = Array(Set(entries.compactMap { $0.browser }))
            RestoreOptionsSheet(
                title: "Restore \(entries.count) Selected Tab\(entries.count == 1 ? "" : "s")",
                sourceBrowsers: entryBrowsers,
                onRestore: { mode, targetBrowser in
                    Task {
                        await viewModel.restoreTabs(entries, mode: mode, targetBrowser: targetBrowser)
                    }
                }
            )
        }
    }
}
