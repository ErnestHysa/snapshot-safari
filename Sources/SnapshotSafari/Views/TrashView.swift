import SwiftUI

struct TrashView: View {
    @Bindable var viewModel: SnapshotListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingConfirmEmpty = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text("Recently Deleted")
                    .font(.title2.bold())

                Text("Snapshots are kept for 30 days before being permanently deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)

            Divider()

            if viewModel.trashedSnapshots.isEmpty {
                ContentUnavailableView(
                    "Trash is Empty",
                    systemImage: "trash.slash",
                    description: Text("Deleted snapshots will appear here.")
                )
            } else {
                List {
                    ForEach(viewModel.trashedSnapshots) { snapshot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.name)
                                    .font(.headline)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text("\(snapshot.tabCount) tab\(snapshot.tabCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let deletedAt = snapshot.deletedAt {
                                        Text("Deleted \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }

                            Spacer()

                            Button {
                                viewModel.restoreFromTrash(snapshot)
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .help("Restore")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.permanentlyDelete(viewModel.trashedSnapshots[index])
                        }
                    }
                }
                .listStyle(.plain)
            }

            // Footer
            HStack(spacing: 12) {
                if !viewModel.trashedSnapshots.isEmpty {
                    Button("Restore All") {
                        viewModel.restoreAllFromTrash()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Empty Trash…", role: .destructive) {
                        showingConfirmEmpty = true
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .frame(width: 460, height: 400)
        .alert("Empty Trash?", isPresented: $showingConfirmEmpty) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                viewModel.emptyTrash()
            }
        } message: {
            Text("This will permanently delete \(viewModel.trashedSnapshots.count) snapshot\(viewModel.trashedSnapshots.count == 1 ? "" : "s"). This action cannot be undone.")
        }
    }
}
