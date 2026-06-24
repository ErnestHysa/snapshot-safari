import SwiftUI

struct CompareSnapshotsView: View {
    let diff: SnapshotDiff
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)

                Text("Snapshot Comparison")
                    .font(.title2.bold())

                HStack(spacing: 4) {
                    Text(diff.older.name)
                        .font(.caption)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(diff.newer.name)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                if diff.isIdentical {
                    Label("No changes — snapshots are identical", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 16) {
                        changeBadge(count: diff.addedTabs.count, label: "added", color: .green)
                        changeBadge(count: diff.removedTabs.count, label: "removed", color: .red)
                        changeBadge(count: diff.commonTabs.count, label: "common", color: .secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)

            Divider()

            // Changes list
            List {
                if !diff.addedTabs.isEmpty {
                    Section {
                        ForEach(diff.addedTabs, id: \.id) { tab in
                            DiffTabRow(tab: tab, change: .added)
                        }
                    } header: {
                        Label("Added (\(diff.addedTabs.count))", systemImage: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !diff.removedTabs.isEmpty {
                    Section {
                        ForEach(diff.removedTabs, id: \.id) { tab in
                            DiffTabRow(tab: tab, change: .removed)
                        }
                    } header: {
                        Label("Removed (\(diff.removedTabs.count))", systemImage: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if !diff.commonTabs.isEmpty {
                    Section {
                        ForEach(diff.commonTabs.prefix(10), id: \.id) { tab in
                            DiffTabRow(tab: tab, change: .common)
                        }
                        if diff.commonTabs.count > 10 {
                            Text("+ \(diff.commonTabs.count - 10) more common tabs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Label("Common (\(diff.commonTabs.count))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)

            // Footer
            HStack {
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
        .frame(width: 500, height: 500)
    }

    private func changeBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Diff Tab Row

private struct DiffTabRow: View {
    enum ChangeType {
        case added, removed, common

        var icon: String {
            switch self {
            case .added: return "plus.circle.fill"
            case .removed: return "minus.circle.fill"
            case .common: return "checkmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .added: return .green
            case .removed: return .red
            case .common: return .secondary
            }
        }
    }

    let tab: TabEntry
    let change: ChangeType

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: change.icon)
                .foregroundStyle(change.color)
                .font(.caption)

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title.isEmpty ? tab.url : tab.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .strikethrough(change == .removed)

                Text(tab.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(tab.domain)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.3))
                .clipShape(Capsule())
                .foregroundStyle(.secondary)
        }
        .opacity(change == .common ? 0.6 : 1.0)
        .padding(.vertical, 2)
    }
}
