import Testing
import Foundation
import SwiftData
@testable import SnapshotSafari

// MARK: - Helpers

/// Creates an in-memory ModelContainer for testing
@MainActor
func createTestContainer() -> ModelContainer {
    let schema = Schema([Snapshot.self, TabEntry.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [config])
}

/// Creates a snapshot with sample tabs for testing
@MainActor
func createSampleSnapshot(in context: ModelContext) -> Snapshot {
    let tabs = [
        TabEntry(url: "https://apple.com", title: "Apple", windowIndex: 0, index: 0),
        TabEntry(url: "https://github.com", title: "GitHub", windowIndex: 0, index: 1),
        TabEntry(url: "https://swift.org", title: "Swift.org", windowIndex: 0, index: 2),
    ]
    let snapshot = Snapshot(name: "Test — Jun 24, 2026 — 3 tabs", tabs: tabs)
    context.insert(snapshot)
    try! context.save()
    return snapshot
}

// MARK: - Tests

@MainActor
struct SnapshotServiceTests {

    // MARK: - Fetch

    @Test("fetchAllSnapshots returns empty for fresh database")
    func fetchEmpty() {
        let container = createTestContainer()
        let service = SnapshotService(modelContext: container.mainContext)

        let snapshots = service.fetchAllSnapshots()

        #expect(snapshots.isEmpty)
    }

    @Test("fetchAllSnapshots returns all snapshots sorted by date descending")
    func fetchAll() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        // Create snapshots with known dates
        let oldSnapshot = Snapshot(name: "Old", tabs: [])
        oldSnapshot.createdAt = Date().addingTimeInterval(-86400) // yesterday
        context.insert(oldSnapshot)

        let newSnapshot = Snapshot(name: "New", tabs: [])
        newSnapshot.createdAt = Date() // now
        context.insert(newSnapshot)

        try! context.save()

        let snapshots = service.fetchAllSnapshots()
        #expect(snapshots.count == 2)
        #expect(snapshots[0].name == "New") // newest first
        #expect(snapshots[1].name == "Old")
    }

    // MARK: - Create

    @Test("creating a snapshot via context works")
    func createSnapshot() {
        let container = createTestContainer()
        let context = container.mainContext

        let tabs = [TabEntry(url: "https://test.com", title: "Test", windowIndex: 0, index: 0)]
        let snapshot = Snapshot(name: "Manual — Jun 24 — 1 tab", tabs: tabs)
        context.insert(snapshot)
        try! context.save()

        let fetched = try! context.fetch(FetchDescriptor<Snapshot>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Manual — Jun 24 — 1 tab")
        #expect(fetched[0].tabCount == 1)
        #expect(fetched[0].tabs.count == 1)
        #expect(fetched[0].tabs[0].url == "https://test.com")
    }

    // MARK: - Rename

    @Test("renameSnapshot updates the name and updatedAt")
    func renameSnapshot() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        let snapshot = createSampleSnapshot(in: context)
        let oldUpdatedAt = snapshot.updatedAt

        // Wait a tiny bit so updatedAt differs
        Thread.sleep(forTimeInterval: 0.01)

        service.renameSnapshot(snapshot, to: "Renamed Snapshot")

        #expect(snapshot.name == "Renamed Snapshot")
        #expect(snapshot.updatedAt > oldUpdatedAt)
    }

    @Test("renameSnapshot persists the change")
    func renamePersists() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        let snapshot = createSampleSnapshot(in: context)
        service.renameSnapshot(snapshot, to: "Persisted Name")

        // Fetch again from context
        let descriptor = FetchDescriptor<Snapshot>()
        let fetched = try! context.fetch(descriptor)
        #expect(fetched[0].name == "Persisted Name")
    }

    // MARK: - Delete

    @Test("deleteSnapshot removes the snapshot and its tabs")
    func deleteSnapshot() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        let snapshot = createSampleSnapshot(in: context)
        #expect(try! context.fetch(FetchDescriptor<Snapshot>()).count == 1)
        #expect(try! context.fetch(FetchDescriptor<TabEntry>()).count == 3)

        service.deleteSnapshot(snapshot)

        #expect(try! context.fetch(FetchDescriptor<Snapshot>()).isEmpty)
        #expect(try! context.fetch(FetchDescriptor<TabEntry>()).isEmpty) // cascade delete
    }

    @Test("deleteSnapshots removes multiple snapshots")
    func deleteMultiple() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        let s1 = createSampleSnapshot(in: context)
        let s2 = createSampleSnapshot(in: context)

        #expect(try! context.fetch(FetchDescriptor<Snapshot>()).count == 2)

        service.deleteSnapshots([s1, s2])

        #expect(try! context.fetch(FetchDescriptor<Snapshot>()).isEmpty)
    }

    // MARK: - Search

    @Test("searchSnapshots with empty query returns all snapshots")
    func searchEmptyQuery() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        createSampleSnapshot(in: context)

        let results = service.searchSnapshots(query: "")
        #expect(results.count == 1)
    }

    @Test("searchSnapshots finds by snapshot name")
    func searchByName() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        createSampleSnapshot(in: context) // name contains "Test"

        let results = service.searchSnapshots(query: "Test")
        #expect(results.count == 1)
    }

    @Test("searchSnapshots finds by tab URL")
    func searchByURL() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        createSampleSnapshot(in: context) // has apple.com tab

        let results = service.searchSnapshots(query: "apple.com")
        #expect(results.count == 1)
    }

    @Test("searchSnapshots finds by tab title")
    func searchByTitle() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        createSampleSnapshot(in: context) // has "GitHub" tab

        let results = service.searchSnapshots(query: "GitHub")
        #expect(results.count == 1)
    }

    @Test("searchSnapshots finds by domain")
    func searchByDomain() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        createSampleSnapshot(in: context) // has swift.org tab

        let results = service.searchSnapshots(query: "swift.org")
        #expect(results.count == 1)
    }

    @Test("searchSnapshots is case-insensitive")
    func searchCaseInsensitive() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        createSampleSnapshot(in: context)

        #expect(service.searchSnapshots(query: "apple").count == 1)
        #expect(service.searchSnapshots(query: "APPLE").count == 1)
        #expect(service.searchSnapshots(query: "Apple").count == 1)
    }

    @Test("searchSnapshots returns empty for no match")
    func searchNoMatch() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        createSampleSnapshot(in: context)

        let results = service.searchSnapshots(query: "nonexistent")
        #expect(results.isEmpty)
    }

    @Test("searchSnapshots finds by partial URL match")
    func searchPartialURL() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        createSampleSnapshot(in: context) // has github.com

        let results = service.searchSnapshots(query: "hub")
        #expect(results.count == 1)
    }

    @Test("searchSnapshots only returns matching snapshots when multiple exist")
    func searchFiltersCorrectly() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = SnapshotService(modelContext: context)

        createSampleSnapshot(in: context) // apple, github, swift

        // Add another snapshot with different content
        let otherTabs = [TabEntry(url: "https://reddit.com", title: "Reddit", windowIndex: 0, index: 0)]
        let other = Snapshot(name: "Other Snapshot", tabs: otherTabs)
        context.insert(other)
        try! context.save()

        let results = service.searchSnapshots(query: "apple")
        #expect(results.count == 1)
        #expect(results[0].name.contains("Test"))
    }

    // MARK: - Tab Count

    @Test("snapshot tabCount property matches tabs array count")
    func tabCountProperty() {
        let container = createTestContainer()
        let context = container.mainContext

        let snapshot = createSampleSnapshot(in: context)
        #expect(snapshot.tabCount == 3)
        #expect(snapshot.tabCount == snapshot.tabs.count)
    }

    // MARK: - Snapshot Init

    @Test("snapshot initializes with isAutoSnapshot flag")
    func autoSnapshotFlag() {
        let container = createTestContainer()
        let context = container.mainContext

        let tabs = [TabEntry(url: "https://test.com", title: "Test", windowIndex: 0, index: 0)]
        let manual = Snapshot(name: "Manual", tabs: tabs, isAutoSnapshot: false)
        let auto = Snapshot(name: "Auto", tabs: tabs, isAutoSnapshot: true)

        context.insert(manual)
        context.insert(auto)
        try! context.save()

        #expect(manual.isAutoSnapshot == false)
        #expect(auto.isAutoSnapshot == true)
    }

    @Test("snapshot timeAgo returns 'Just now' for fresh snapshots")
    func timeAgoJustNow() {
        let tabs = [TabEntry(url: "https://test.com", title: "Test", windowIndex: 0, index: 0)]
        let snapshot = Snapshot(name: "Fresh", tabs: tabs)
        #expect(snapshot.timeAgo == "Just now")
    }

    @Test("snapshot formattedDate is not empty")
    func formattedDateNotEmpty() {
        let tabs = [TabEntry(url: "https://test.com", title: "Test", windowIndex: 0, index: 0)]
        let snapshot = Snapshot(name: "Test", tabs: tabs)
        #expect(snapshot.formattedDate.isEmpty == false)
    }
}
