import SwiftUI

struct SnapshotCard: View {
    let snapshot: Snapshot

    private let faviconService = FaviconService()
    @State private var previewFavicons: [NSImage?] = []
    @State private var isHovering = false

    private let maxPreviewFavicons = 5

    var body: some View {
        HStack(spacing: 12) {
            // Favicon preview column
            VStack(alignment: .leading, spacing: 2) {
                if !previewFavicons.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(0..<min(previewFavicons.count, maxPreviewFavicons), id: \.self) { index in
                            if let image = previewFavicons[index] {
                                Image(nsImage: image)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        if snapshot.tabCount > maxPreviewFavicons {
                            Text("+\(snapshot.tabCount - maxPreviewFavicons)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 80, alignment: .leading)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label("\(snapshot.tabCount) tab\(snapshot.tabCount == 1 ? "" : "s")", systemImage: "square.on.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(snapshot.timeAgo)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if snapshot.isAutoSnapshot {
                        Label("Auto", systemImage: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            loadPreviewFavicons()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.name)
        .accessibilityValue("\(snapshot.tabCount) tabs, \(snapshot.timeAgo)")
    }

    private func loadPreviewFavicons() {
        let domains = Set(snapshot.tabs.prefix(maxPreviewFavicons).map { $0.domain })
        Task {
            var icons: [NSImage?] = []
            for domain in domains {
                if let image = await faviconService.favicon(for: domain) {
                    icons.append(image)
                }
            }
            previewFavicons = icons
        }
    }
}
