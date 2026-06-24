import Foundation
import SwiftData

@Model
final class Snapshot {
    #Unique<Snapshot>([\.id])

    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isAutoSnapshot: Bool
    @Relationship(deleteRule: .cascade, inverse: \TabEntry.snapshot) var tabs: [TabEntry]

    var tabCount: Int {
        tabs.count
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(createdAt)
        switch interval {
        case ..<60: return "Just now"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86400: return "\(Int(interval / 3600))h ago"
        case ..<2592000: return "\(Int(interval / 86400))d ago"
        default: return formattedDate
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        tabs: [TabEntry],
        isAutoSnapshot: Bool = false
    ) {
        self.id = id
        self.name = name
        self.tabs = tabs
        self.isAutoSnapshot = isAutoSnapshot
        self.createdAt = Date()
        self.updatedAt = Date()
        // Set the inverse relationship so SwiftData can validate it
        for tab in tabs {
            tab.snapshot = self
        }
    }
}
