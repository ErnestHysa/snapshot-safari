import Foundation

// MARK: - Snapshot Comparison

/// Represents the diff between two snapshots.
struct SnapshotDiff: Identifiable, Equatable {
    let id = UUID()
    let older: Snapshot
    let newer: Snapshot

    /// Tabs present in the older snapshot but not in the newer one (closed tabs)
    let removedTabs: [TabEntry]
    /// Tabs present in the newer snapshot but not in the older one (new tabs)
    let addedTabs: [TabEntry]
    /// Tabs present in both snapshots
    let commonTabs: [TabEntry]

    var changeCount: Int { removedTabs.count + addedTabs.count }

    var isIdentical: Bool { removedTabs.isEmpty && addedTabs.isEmpty }

    /// Compute diff between two snapshots.
    /// Tabs are matched by URL (case-insensitive).
    static func compute(between older: Snapshot, and newer: Snapshot) -> SnapshotDiff {
        let olderURLs = Set(older.tabs.map { $0.url.lowercased() })
        let newerURLs = Set(newer.tabs.map { $0.url.lowercased() })

        let removed = older.tabs.filter { !newerURLs.contains($0.url.lowercased()) }
        let added = newer.tabs.filter { !olderURLs.contains($0.url.lowercased()) }
        let common = older.tabs.filter { newerURLs.contains($0.url.lowercased()) }

        return SnapshotDiff(
            older: older,
            newer: newer,
            removedTabs: removed,
            addedTabs: added,
            commonTabs: common
        )
    }

    static func == (lhs: SnapshotDiff, rhs: SnapshotDiff) -> Bool {
        lhs.id == rhs.id
    }
}
