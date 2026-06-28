import SwiftUI
import SwiftData

struct SnapshotListView: View {
    @Bindable var viewModel: SnapshotListViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Browser filter picker
            if !viewModel.availableBrowserFilters.isEmpty {
                Picker("Filter", selection: $viewModel.browserFilter) {
                    ForEach(viewModel.availableBrowserFilters, id: \.self) { filter in
                        HStack(spacing: 4) {
                            Image(systemName: filter.iconName)
                                .font(.system(size: 10))
                            Text(filter.label)
                        }
                        .tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .padding(.vertical, 6)

                Divider()
            }

            List(selection: $viewModel.selectedSnapshot) {
                ForEach(viewModel.filteredSnapshots) { snapshot in
                    NavigationLink(value: snapshot) {
                        SnapshotCard(snapshot: snapshot)
                    }
                    .accessibilityLabel("\(snapshot.name), \(snapshot.tabCount) tabs, \(snapshot.timeAgo)")
                    .accessibilityHint("Select to view and restore tabs from this snapshot.")
                    .contextMenu {
                        Button("Rename…") {
                            viewModel.selectedSnapshot = snapshot
                        }
                        .accessibilityLabel("Rename this snapshot")

                        Button("Export…") {
                            viewModel.exportSnapshot(snapshot)
                        }
                        .accessibilityLabel("Export this snapshot to a file")

                        if viewModel.snapshots.count >= 2 {
                            Menu("Compare With…") {
                                ForEach(viewModel.snapshots.filter { $0.id != snapshot.id }) { other in
                                    Button(other.name) {
                                        if snapshot.createdAt < other.createdAt {
                                            viewModel.compareSnapshots(snapshot, other)
                                        } else {
                                            viewModel.compareSnapshots(other, snapshot)
                                        }
                                    }
                                    .accessibilityLabel("Compare with \(other.name)")
                                }
                            }
                        }

                        Divider()

                        Button("Delete", role: .destructive) {
                            viewModel.deleteSnapshot(snapshot)
                        }
                        .accessibilityLabel("Delete this snapshot")
                        .accessibilityHint("Moves this snapshot to the trash.")
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let snapshot = viewModel.filteredSnapshots[index]
                        viewModel.deleteSnapshot(snapshot)
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search snapshots…")
            .navigationTitle("Snapshots")
            .overlay {
                if viewModel.filteredSnapshots.isEmpty {
                    if !viewModel.searchText.isEmpty {
                        ContentUnavailableView.search(text: viewModel.searchText)
                    } else if viewModel.browserFilter != .all {
                        ContentUnavailableView(
                            "No \(viewModel.browserFilter.label) Snapshots",
                            systemImage: viewModel.browserFilter.iconName,
                            description: Text("Try selecting a different browser filter.")
                        )
                    } else {
                        ContentUnavailableView(
                            "No Snapshots Yet",
                            systemImage: "camera",
                            description: Text("Take your first snapshot with ⌘N")
                        )
                    }
                }
            }
            .refreshable {
                viewModel.refresh()
            }
        }
    }
}
