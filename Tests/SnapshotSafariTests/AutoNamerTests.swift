import Testing
import Foundation
@testable import SnapshotSafari

struct AutoNamerTests {

    @Test("Manual snapshot name starts with 'Snapshot'")
    func manualSnapshotPrefix() {
        let name = AutoNamer.generateName(tabCount: 5, isAuto: false)
        #expect(name.hasPrefix("Snapshot"))
    }

    @Test("Auto snapshot name starts with 'Auto'")
    func autoSnapshotPrefix() {
        let name = AutoNamer.generateName(tabCount: 3, isAuto: true)
        #expect(name.hasPrefix("Auto"))
    }

    @Test("Name contains the tab count")
    func containsTabCount() {
        let name = AutoNamer.generateName(tabCount: 10)
        #expect(name.contains("10"))
    }

    @Test("Name uses 'tabs' plural for multiple tabs")
    func pluralTabs() {
        let name = AutoNamer.generateName(tabCount: 2)
        #expect(name.hasSuffix("tabs"))
    }

    @Test("Name uses 'tab' singular for one tab")
    func singularTab() {
        let name = AutoNamer.generateName(tabCount: 1)
        #expect(name.hasSuffix("tab"))
    }

    @Test("Name handles zero tabs")
    func zeroTabs() {
        let name = AutoNamer.generateName(tabCount: 0)
        #expect(name.hasSuffix("tabs"))
    }

    @Test("Name contains the date (abbreviated format)")
    func containsDate() {
        let name = AutoNamer.generateName(tabCount: 5)
        let datePart = Date.now.formatted(date: .abbreviated, time: .omitted)
        #expect(name.contains(datePart))
    }

    @Test("Name uses em dash separators")
    func usesEmDash() {
        let name = AutoNamer.generateName(tabCount: 4)
        #expect(name.contains(" — "))
    }

    @Test("Snapshot with 100 tabs is formatted correctly")
    func hundredTabs() {
        let name = AutoNamer.generateName(tabCount: 100)
        #expect(name.contains("100"))
        #expect(name.hasSuffix("tabs"))
    }

    @Test("Auto snapshot name does not equal manual snapshot name for same tab count")
    func autoVsManualDifference() {
        let autoName = AutoNamer.generateName(tabCount: 5, isAuto: true)
        let manualName = AutoNamer.generateName(tabCount: 5, isAuto: false)
        #expect(autoName != manualName)
        #expect(autoName.hasPrefix("Auto"))
        #expect(manualName.hasPrefix("Snapshot"))
    }
}
