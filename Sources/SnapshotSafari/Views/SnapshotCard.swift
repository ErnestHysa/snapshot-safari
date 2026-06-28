import SwiftUI

struct SnapshotCard: View {
    let snapshot: Snapshot

    private let faviconService = FaviconService()
    @State private var previewFavicons: [NSImage?] = []
    @State private var isHovering = false

    private let maxPreviewFavicons = 5

    /// Unique browsers in this snapshot.
    private var browsers: [Browser] {
        let ids = Set(snapshot.tabs.map { $0.browserId })
        return ids.compactMap { Browser(rawValue: $0) }.sorted { $0.displayName < $1.displayName }
    }

    /// Whether this snapshot contains tabs from multiple browsers.
    private var isMultiBrowser: Bool {
        browsers.count > 1
    }

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

                    // Multi-browser indicator: "Capture All" badge + browser pills
                    if isMultiBrowser {
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
