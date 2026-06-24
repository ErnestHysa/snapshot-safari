import Testing
import Foundation
import SwiftData
@testable import SnapshotSafari

// MARK: - SnapshotExport Tests

struct SnapshotExportTests {

    // MARK: - Export Model Tests

    @Test("export JSON encodes and decodes roundtrip")
    func exportRoundtrip() throws {
        let tabs = [
            SnapshotExport.ExportedTab(url: "https://apple.com", title: "Apple", windowIndex: 0, index: 0),
            SnapshotExport.ExportedTab(url: "https://github.com", title: "GitHub", windowIndex: 0, index: 1),
        ]
        let exported = SnapshotExport.ExportedSnapshot(
            name: "Test Snapshot",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isAutoSnapshot: false,
            tabs: tabs
        )
        let export = SnapshotExport(
            version: SnapshotExport.currentVersion,
            app: SnapshotExport.appName,
            exportDate: Date(timeIntervalSince1970: 1_700_000_000),
            snapshots: [exported]
        )

        let data = try export.jsonData()
        let decoded = try SnapshotExport.from(jsonData: data)

        #expect(decoded.version == SnapshotExport.currentVersion)
        #expect(decoded.app == SnapshotExport.appName)
        #expect(decoded.snapshots.count == 1)
        #expect(decoded.snapshots[0].name == "Test Snapshot")
        #expect(decoded.snapshots[0].tabs.count == 2)
        #expect(decoded.snapshots[0].tabs[0].url == "https://apple.com")
        #expect(decoded.snapshots[0].isAutoSnapshot == false)
    }

    @Test("export handles auto snapshots flag")
    func exportAutoFlag() throws {
        let tabs = [SnapshotExport.ExportedTab(url: "https://test.com", title: "Test", windowIndex: 0, index: 0)]
        let exported = SnapshotExport.ExportedSnapshot(
            name: "Auto Snapshot",
            createdAt: Date(),
            isAutoSnapshot: true,
            tabs: tabs
        )
        let export = SnapshotExport(
            version: SnapshotExport.currentVersion,
            app: SnapshotExport.appName,
            exportDate: Date(),
            snapshots: [exported]
        )

        let data = try export.jsonData()
        let decoded = try SnapshotExport.from(jsonData: data)

        #expect(decoded.snapshots[0].isAutoSnapshot == true)
    }

    @Test("export handles empty tabs array")
    func exportEmptyTabs() throws {
        let exported = SnapshotExport.ExportedSnapshot(
            name: "Empty",
            createdAt: Date(),
            isAutoSnapshot: false,
            tabs: []
        )
        let export = SnapshotExport(
            version: SnapshotExport.currentVersion,
            app: SnapshotExport.appName,
            exportDate: Date(),
            snapshots: [exported]
        )

        let data = try export.jsonData()
        let decoded = try SnapshotExport.from(jsonData: data)

        #expect(decoded.snapshots[0].tabs.isEmpty)
    }

    @Test("export handles multiple snapshots")
    func exportMultiple() throws {
        let snapshots = (1...3).map { i in
            SnapshotExport.ExportedSnapshot(
                name: "Snapshot \(i)",
                createdAt: Date(),
                isAutoSnapshot: false,
                tabs: [
                    SnapshotExport.ExportedTab(url: "https://site\(i).com", title: "Site \(i)", windowIndex: 0, index: 0)
                ]
            )
        }
        let export = SnapshotExport(
            version: SnapshotExport.currentVersion,
            app: SnapshotExport.appName,
            exportDate: Date(),
            snapshots: snapshots
        )

        let data = try export.jsonData()
        let decoded = try SnapshotExport.from(jsonData: data)

        #expect(decoded.snapshots.count == 3)
        #expect(decoded.snapshots[0].name == "Snapshot 1")
        #expect(decoded.snapshots[2].name == "Snapshot 3")
    }

    @Test("jsonData produces valid JSON format")
    func jsonFormat() throws {
        let exported = SnapshotExport.ExportedSnapshot(
            name: "Test",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isAutoSnapshot: false,
            tabs: [
                SnapshotExport.ExportedTab(url: "https://test.com", title: "Test", windowIndex: 0, index: 0)
            ]
        )
        let export = SnapshotExport(
            version: SnapshotExport.currentVersion,
            app: SnapshotExport.appName,
            exportDate: Date(timeIntervalSince1970: 1_700_000_000),
            snapshots: [exported]
        )

        let data = try export.jsonData()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil)
        #expect(json?["version"] as? Int == SnapshotExport.currentVersion)
        #expect(json?["app"] as? String == SnapshotExport.appName)
        #expect(json?["snapshots"] as? [[String: Any]] != nil)
    }

    @Test("ExportedTab Equatable conformance works correctly")
    func exportedTabEquatable() throws {
        let tab1 = SnapshotExport.ExportedTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0)
        let tab2 = SnapshotExport.ExportedTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0)
        let tab3 = SnapshotExport.ExportedTab(url: "https://b.com", title: "B", windowIndex: 0, index: 0)

        #expect(tab1 == tab2)
        #expect(tab1 != tab3)
    }

}

// MARK: - SnapshotService Export/Import Integration

@MainActor
struct SnapshotServiceExportTests {

    @Test("from creates export from Snapshot model objects")
    func createFromSnapshots() throws {
        let context = try makeContext()

        let tabs = [
            TabEntry(url: "https://apple.com", title: "Apple", windowIndex: 0, index: 0),
            TabEntry(url: "https://github.com", title: "GitHub", windowIndex: 0, index: 1),
        ]
        let snapshot = Snapshot(name: "Test Snapshot", tabs: tabs, isAutoSnapshot: true)
        context.insert(snapshot)
        try context.save()

        let export = SnapshotExport.create(from: [snapshot])

        #expect(export.version == SnapshotExport.currentVersion)
        #expect(export.app == SnapshotExport.appName)
        #expect(export.snapshots.count == 1)
        #expect(export.snapshots[0].name == "Test Snapshot")
        #expect(export.snapshots[0].isAutoSnapshot == true)
        #expect(export.snapshots[0].tabs.count == 2)
        #expect(export.snapshots[0].tabs[0].url == "https://apple.com")
        #expect(export.snapshots[0].tabs[1].url == "https://github.com")
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Snapshot.self, TabEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    @Test("exportSnapshotToJSON produces valid data")
    func exportServiceJSON() throws {
        let context = try makeContext()
        let service = SnapshotService(modelContext: context)

        let tabs = [
            TabEntry(url: "https://apple.com", title: "Apple", windowIndex: 0, index: 0),
        ]
        let snapshot = Snapshot(name: "Export Test", tabs: tabs)
        context.insert(snapshot)
        try context.save()

        let data = try service.exportSnapshotToJSON(snapshot)

        // Verify it roundtrips
        let export = try SnapshotExport.from(jsonData: data)
        #expect(export.snapshots.count == 1)
        #expect(export.snapshots[0].name == "Export Test")
        #expect(export.snapshots[0].tabs.count == 1)
        #expect(export.snapshots[0].tabs[0].url == "https://apple.com")
    }

    @Test("exportMultipleSnapshotsToJSON exports all snapshots")
    func exportMultipleService() throws {
        let context = try makeContext()
        let service = SnapshotService(modelContext: context)

        let s1 = Snapshot(name: "First", tabs: [
            TabEntry(url: "https://a.com", title: "A", windowIndex: 0, index: 0)
        ])
        let s2 = Snapshot(name: "Second", tabs: [
            TabEntry(url: "https://b.com", title: "B", windowIndex: 0, index: 0)
        ])
        context.insert(s1)
        context.insert(s2)
        try context.save()

        let data = try service.exportMultipleSnapshotsToJSON([s1, s2])
        let export = try SnapshotExport.from(jsonData: data)

        #expect(export.snapshots.count == 2)
        #expect(export.snapshots[0].name == "First")
        #expect(export.snapshots[1].name == "Second")
    }

    @Test("importSnapshots imports and creates SwiftData objects")
    func importService() throws {
        let context = try makeContext()
        let service = SnapshotService(modelContext: context)

        // Create export data
        let tabs = [
            SnapshotExport.ExportedTab(url: "https://imported.com", title: "Imported", windowIndex: 0, index: 0),
        ]
        let exportedSnapshot = SnapshotExport.ExportedSnapshot(
            name: "Imported Snapshot",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isAutoSnapshot: false,
            tabs: tabs
        )
        let export = SnapshotExport(
            version: SnapshotExport.currentVersion,
            app: SnapshotExport.appName,
            exportDate: Date(),
            snapshots: [exportedSnapshot]
        )

        let data = try export.jsonData()
        let count = try service.importSnapshots(from: data)

        #expect(count == 1)

        // Verify it was imported
        let all = service.fetchAllSnapshots()
        #expect(all.count == 1)
        #expect(all[0].name == "Imported Snapshot")
        #expect(all[0].tabs.count == 1)
        #expect(all[0].tabs[0].url == "https://imported.com")
        // Original creation date should be preserved
        #expect(all[0].createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("import multiple snapshots at once")
    func importMultiple() throws {
        let context = try makeContext()
        let service = SnapshotService(modelContext: context)

        let snapshots = (1...3).map { i in
            SnapshotExport.ExportedSnapshot(
                name: "Imported \(i)",
                createdAt: Date(),
                isAutoSnapshot: false,
                tabs: [
                    SnapshotExport.ExportedTab(url: "https://site\(i).com", title: "Site \(i)", windowIndex: 0, index: 0)
                ]
            )
        }
        let export = SnapshotExport(
            version: SnapshotExport.currentVersion,
            app: SnapshotExport.appName,
            exportDate: Date(),
            snapshots: snapshots
        )

        let data = try export.jsonData()
        let count = try service.importSnapshots(from: data)

        #expect(count == 3)
        #expect(service.fetchAllSnapshots().count == 3)
    }

    @Test("import rejects unsupported version")
    func unsupportedVersion() throws {
        let context = try makeContext()
        let service = SnapshotService(modelContext: context)

        let exported = SnapshotExport.ExportedSnapshot(
            name: "Test",
            createdAt: Date(),
            isAutoSnapshot: false,
            tabs: []
        )
        let export = SnapshotExport(
            version: 999, // Unsupported version
            app: SnapshotExport.appName,
            exportDate: Date(),
            snapshots: [exported]
        )

        let data = try export.jsonData()

        #expect(throws: SnapshotService.ExportError.unsupportedVersion(999)) {
            try service.importSnapshots(from: data)
        }
    }

    @Test("export then import roundtrips correctly")
    func exportImportRoundtrip() throws {
        let context = try makeContext()
        let service = SnapshotService(modelContext: context)

        // Create a snapshot
        let tabs = [
            TabEntry(url: "https://apple.com", title: "Apple", windowIndex: 0, index: 0),
            TabEntry(url: "https://github.com", title: "GitHub", windowIndex: 1, index: 2),
        ]
        let snapshot = Snapshot(name: "Roundtrip Test", tabs: tabs, isAutoSnapshot: true)
        context.insert(snapshot)
        try context.save()

        // Export
        let data = try service.exportSnapshotToJSON(snapshot)

        // Import into a fresh context
        let freshContext = try makeContext()
        let freshService = SnapshotService(modelContext: freshContext)
        let count = try freshService.importSnapshots(from: data)

        #expect(count == 1)

        let imported = freshService.fetchAllSnapshots()
        #expect(imported[0].name == "Roundtrip Test")
        #expect(imported[0].isAutoSnapshot == true)
        #expect(imported[0].tabs.count == 2)
        #expect(imported[0].tabs[0].url == "https://apple.com")
        #expect(imported[0].tabs[1].url == "https://github.com")
        #expect(imported[0].tabs[1].windowIndex == 1)
        #expect(imported[0].tabs[1].index == 2)
    }
}
