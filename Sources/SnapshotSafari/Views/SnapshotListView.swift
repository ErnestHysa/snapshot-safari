import SwiftUI
import SwiftData

struct SnapshotListView: View {
    @Bindable var viewModel: SnapshotListViewModel

    var body: some View {
        List(selection: $viewModel.selectedSnapshot) {
            ForEach(viewModel.filteredSnapshots) { snapshot in
                NavigationLink(value: snapshot) {
                    SnapshotCard(snapshot: snapshot)
                }
                .contextMenu {
                    Button("Rename…") {
                        viewModel.selectedSnapshot = snapshot
                    }
                    Button("Delete", role: .destructive) {
                        viewModel.deleteSnapshot(snapshot)
                    }
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
                if viewModel.searchText.isEmpty {
                    ContentUnavailableView(
                        "No Snapshots Yet",
                        systemImage: "camera",
                        description: Text("Take your first snapshot with ⌘N")
                    )
                } else {
                    ContentUnavailableView.search(text: viewModel.searchText)
                }
            }
        }
        .refreshable {
            viewModel.refresh()
        }
    }
}
