import Foundation

enum AutoNamer {
    static func generateName(tabCount: Int, isAuto: Bool = false, browserName: String? = nil) -> String {
        let datePart = Date.now.formatted(date: .abbreviated, time: .omitted)
        let prefix = isAuto ? "Auto" : "Snapshot"
        let browser = browserName.map { " — \($0)" } ?? ""
        return "\(prefix)\(browser) — \(datePart) — \(tabCount) tab\(tabCount == 1 ? "" : "s")"
    }
}
