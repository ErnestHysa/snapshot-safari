import Testing
import Foundation
@testable import SnapshotSafari

// MARK: - SettingsTab Tests

struct SettingsTabTests {

    @Test("SettingsTab has seven cases in stable order")
    func sevenCases() {
        let all = SettingsTab.allCases
        #expect(all.count == 7)
        #expect(all[0] == .general)
        #expect(all[1] == .autoSnapshots)
        #expect(all[2] == .sync)
        #expect(all[3] == .appearance)
        #expect(all[4] == .permissions)
        #expect(all[5] == .updates)
        #expect(all[6] == .about)
    }

    @Test("SettingsTab raw values match their display names")
    func rawValues() {
        #expect(SettingsTab.general.rawValue == "General")
        #expect(SettingsTab.autoSnapshots.rawValue == "Auto-Snapshots")
        #expect(SettingsTab.sync.rawValue == "iCloud Sync")
        #expect(SettingsTab.appearance.rawValue == "Appearance")
        #expect(SettingsTab.permissions.rawValue == "Permissions")
        #expect(SettingsTab.updates.rawValue == "Updates")
        #expect(SettingsTab.about.rawValue == "About")
    }

    @Test("SettingsTab ids are unique")
    func uniqueIds() {
        let allIds = SettingsTab.allCases.map(\.id)
        let uniqueIds = Set(allIds)
        #expect(allIds.count == uniqueIds.count)
    }

    @Test("SettingsTab icons are all SF Symbol names")
    func iconsAreSFSymbols() {
        for tab in SettingsTab.allCases {
            // SF Symbol names are non-empty ASCII without spaces.
            #expect(!tab.icon.isEmpty)
            #expect(!tab.icon.contains(" "))
        }
    }
}

// MARK: - AppTheme Tests

struct AppThemeTests {

    @Test("AppTheme has three cases")
    func threeCases() {
        #expect(AppTheme.allCases.count == 3)
    }

    @Test("AppTheme system maps to nil colorScheme")
    func systemNilScheme() {
        #expect(AppTheme.system.colorScheme == nil)
    }

    @Test("AppTheme light maps to .light colorScheme")
    func lightScheme() {
        #expect(AppTheme.light.colorScheme == .light)
    }

    @Test("AppTheme dark maps to .dark colorScheme")
    func darkScheme() {
        #expect(AppTheme.dark.colorScheme == .dark)
    }

    @Test("AppTheme icons are non-empty SF Symbols")
    func iconsValid() {
        for theme in AppTheme.allCases {
            #expect(!theme.icon.isEmpty)
        }
    }

    @Test("AppTheme ids are unique")
    func uniqueIds() {
        let ids = AppTheme.allCases.map(\.id)
        #expect(ids.count == Set(ids).count)
    }
}