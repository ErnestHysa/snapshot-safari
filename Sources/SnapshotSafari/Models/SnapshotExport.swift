import Foundation

// MARK: - Export / Import

/// Represents an exported snapshot in JSON format.
struct SnapshotExport: Codable, Equatable {
    let version: Int
    let app: String
    let exportDate: Date
    let snapshots: [ExportedSnapshot]

    static let currentVersion = 1
    static let appName = "Snapshot Safari"

    struct ExportedSnapshot: Codable, Equatable {
        let name: String
        let createdAt: Date
        let isAutoSnapshot: Bool
        let tabs: [ExportedTab]
    }

    struct ExportedTab: Codable, Equatable {
        let url: String
        let title: String
        let windowIndex: Int
        let index: Int
    }

    /// Create an export from an array of Snapshots.
    static func create(from snapshots: [Snapshot]) -> SnapshotExport {
        SnapshotExport(
            version: currentVersion,
            app: appName,
            exportDate: Date(),
            snapshots: snapshots.map { snapshot in
                ExportedSnapshot(
                    name: snapshot.name,
                    createdAt: snapshot.createdAt,
                    isAutoSnapshot: snapshot.isAutoSnapshot,
                    tabs: snapshot.tabs.map { tab in
                        ExportedTab(
                            url: tab.url,
                            title: tab.title,
                            windowIndex: tab.windowIndex,
                            index: tab.index
                        )
                    }
                )
            }
        )
    }

    /// Encode to JSON data.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decode from JSON data.
    static func from(jsonData: Data) throws -> SnapshotExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SnapshotExport.self, from: jsonData)
    }
}
