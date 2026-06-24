import Testing
import Foundation
import SwiftData
@testable import SnapshotSafari

// MARK: - SnapshotDiff Tests

/// Tests the core diff algorithm logic without SwiftData models.
/// The SnapshotDiff algorithm works by comparing URL sets (case-insensitive),
/// so we can test it with simple URL strings.
@MainActor
struct SnapshotDiffTests {

    // MARK: - Pure Logic Tests (no SwiftData)

    @Test("diff between two identical URL sets shows no changes")
    func identicalSets() {
        let result = diffURLs(older: [
            "https://apple.com",
            "https://github.com",
        ], newer: [
            "https://apple.com",
            "https://github.com",
        ])

        #expect(result.added.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.common.count == 2)
        #expect(result.changeCount == 0)
    }

    @Test("diff detects added URLs")
    func addedURLs() {
        let result = diffURLs(older: [
            "https://apple.com",
        ], newer: [
            "https://apple.com",
            "https://github.com",
            "https://swift.org",
        ])

        #expect(result.added.count == 2)
        #expect(result.removed.isEmpty)
        #expect(result.common.count == 1)
        #expect(result.changeCount == 2)
    }

    @Test("diff detects removed URLs")
    func removedURLs() {
        let result = diffURLs(older: [
            "https://apple.com",
            "https://github.com",
            "https://swift.org",
        ], newer: [
            "https://apple.com",
        ])

        #expect(result.added.isEmpty)
        #expect(result.removed.count == 2)
        #expect(result.common.count == 1)
        #expect(result.changeCount == 2)
    }

    @Test("diff detects both added and removed URLs")
    func addedAndRemovedURLs() {
        let result = diffURLs(older: [
            "https://apple.com",
            "https://old-site.com",
        ], newer: [
            "https://apple.com",
            "https://new-site.com",
        ])

        #expect(result.added.count == 1)
        #expect(result.removed.count == 1)
        #expect(result.common.count == 1)
        #expect(result.changeCount == 2)
    }

    @Test("diff matching is case-insensitive for URLs")
    func caseInsensitiveMatch() {
        let result = diffURLs(older: [
            "https://Apple.com/Home",
        ], newer: [
            "https://apple.com/home",
        ])

        #expect(result.added.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.common.count == 1)
    }

    @Test("diff handles empty URL sets")
    func emptyOlder() {
        let result = diffURLs(older: [], newer: [
            "https://apple.com",
        ])

        #expect(!result.added.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.common.isEmpty)
    }

    @Test("diff handles both empty URL sets")
    func bothEmpty() {
        let result = diffURLs(older: [], newer: [])

        #expect(result.added.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.common.isEmpty)
        #expect(result.changeCount == 0)
    }

    @Test("diff with many URLs handles all categories correctly")
    func manyURLs() {
        let older = (1...20).map { "https://site\($0).com" }
        let newer = (11...30).map { "https://site\($0).com" }

        let result = diffURLs(older: older, newer: newer)

        // Sites 1-10 are only in older (removed), 11-20 are common, 21-30 are only in newer (added)
        #expect(result.removed.count == 10)  // 1-10
        #expect(result.common.count == 10)   // 11-20
        #expect(result.added.count == 10)    // 21-30
        #expect(result.changeCount == 20)
    }

    // MARK: - SnapshotDiff Integration Test

    @Test("SnapshotDiff.compute produces correct diff from Snapshot objects")
    func snapshotDiffIntegration() throws {
        // Use an in-memory context to avoid @Relationship inverse issues
        let schema = Schema([Snapshot.self, TabEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let olderTabs = [
            TabEntry(url: "https://apple.com", title: "Apple", windowIndex: 0, index: 0),
            TabEntry(url: "https://github.com", title: "GitHub", windowIndex: 0, index: 1),
        ]
        let older = Snapshot(name: "First", tabs: olderTabs)
        context.insert(older)

        let newerTabs = [
            TabEntry(url: "https://apple.com", title: "Apple", windowIndex: 0, index: 0),
            TabEntry(url: "https://swift.org", title: "Swift", windowIndex: 0, index: 1),
        ]
        let newer = Snapshot(name: "Second", tabs: newerTabs)
        context.insert(newer)

        try context.save()

        let diff = SnapshotDiff.compute(between: older, and: newer)

        #expect(!diff.isIdentical)
        #expect(diff.addedTabs.count == 1)
        #expect(diff.removedTabs.count == 1)
        #expect(diff.commonTabs.count == 1)
        #expect(diff.changeCount == 2)
        #expect(diff.older.name == "First")
        #expect(diff.newer.name == "Second")
    }
}

// MARK: - Pure logic helper

/// A pure function that implements the same URL matching algorithm as SnapshotDiff.compute,
/// but works with strings instead of Snapshot/TabEntry objects.
private func diffURLs(older: [String], newer: [String]) -> (added: [String], removed: [String], common: [String], changeCount: Int) {
    let olderSet = Set(older.map { $0.lowercased() })
    let newerSet = Set(newer.map { $0.lowercased() })

    let removed = older.filter { !newerSet.contains($0.lowercased()) }
    let added = newer.filter { !olderSet.contains($0.lowercased()) }
    let common = older.filter { newerSet.contains($0.lowercased()) }

    return (added, removed, common, added.count + removed.count)
}
