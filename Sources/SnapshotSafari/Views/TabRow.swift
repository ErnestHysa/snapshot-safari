import SwiftUI

struct TabRow: View {
    let tab: TabEntry

    private let faviconService = FaviconService()
    @State private var favicon: NSImage?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Favicon
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title.isEmpty ? tab.url : tab.title)
                    .font(.body)
                    .lineLimit(1)

                Text(tab.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Domain badge
            Text(tab.domain)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.3))
                .clipShape(Capsule())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.gray.opacity(0.12) : Color.clear)
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            loadFavicon()
        }
    }

    private func loadFavicon() {
        Task {
            favicon = await faviconService.favicon(for: tab.domain)
        }
    }
}
