import Foundation
import SwiftData

@Model
final class TabEntry {
    var id: UUID
    var url: String
    var domain: String
    var title: String
    var windowIndex: Int
    var index: Int
    /// Bundle identifier of the browser this tab came from (e.g. "com.apple.Safari").
    var browserId: String
    var snapshot: Snapshot?

    /// The browser this tab belongs to, if recognized.
    var browser: Browser? { Browser(rawValue: browserId) }

    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        windowIndex: Int,
        index: Int,
        browserId: String = Browser.safari.rawValue
    ) {
        self.id = id
        self.url = url
        self.domain = URL(string: url)?.host ?? url
        self.title = title
        self.windowIndex = windowIndex
        self.index = index
        self.browserId = browserId
    }
}
