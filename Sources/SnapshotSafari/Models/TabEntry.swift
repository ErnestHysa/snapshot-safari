import Foundation
import SwiftData

@Model
final class TabEntry {
    #Unique<TabEntry>([\.id])

    var id: UUID
    var url: String
    var domain: String
    var title: String
    var windowIndex: Int
    var index: Int
    var snapshot: Snapshot?

    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        windowIndex: Int,
        index: Int
    ) {
        self.id = id
        self.url = url
        self.domain = URL(string: url)?.host ?? url
        self.title = title
        self.windowIndex = windowIndex
        self.index = index
    }
}
