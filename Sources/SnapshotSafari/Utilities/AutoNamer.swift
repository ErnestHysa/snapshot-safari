import Foundation

enum AutoNamer {
    static func generateName(tabCount: Int, isAuto: Bool = false) -> String {
        let datePart = Date.now.formatted(date: .abbreviated, time: .omitted)
        let prefix = isAuto ? "Auto" : "Snapshot"
        return "\(prefix) — \(datePart) — \(tabCount) tab\(tabCount == 1 ? "" : "s")"
    }
}
