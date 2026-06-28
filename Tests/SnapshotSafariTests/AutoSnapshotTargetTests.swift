import Testing
import Foundation
@testable import SnapshotSafari

// MARK: - AutoSnapshotTarget Tests

struct AutoSnapshotTargetTests {

    // MARK: - Static Constants

    @Test("frontmost target has correct id, label, icon, and nil browser")
    func frontmostTarget() {
        let target = AutoSnapshotTarget.frontmost
        #expect(target.id == "frontmost")
        #expect(target.label == "Frontmost Browser")
        #expect(target.icon == "rectangle.badge.checkmark")
        #expect(target.browser == nil)
    }

    @Test("allRunning target has correct id, label, icon, and nil browser")
    func allRunningTarget() {
        let target = AutoSnapshotTarget.allRunning
        #expect(target.id == "allRunning")
        #expect(target.label == "All Running Browsers")
        #expect(target.icon == "square.grid.2x2")
        #expect(target.browser == nil)
    }

    // MARK: - resolve() with new id format

    @Test("resolve(\"frontmost\") returns .frontmost")
    func resolveFrontmost() {
        let resolved = AutoSnapshotTarget.resolve(id: "frontmost")
        #expect(resolved.id == AutoSnapshotTarget.frontmost.id)
        #expect(resolved.label == AutoSnapshotTarget.frontmost.label)
        #expect(resolved.browser == nil)
    }

    @Test("resolve(\"allRunning\") returns .allRunning")
    func resolveAllRunning() {
        let resolved = AutoSnapshotTarget.resolve(id: "allRunning")
        #expect(resolved.id == AutoSnapshotTarget.allRunning.id)
        #expect(resolved.label == AutoSnapshotTarget.allRunning.label)
        #expect(resolved.browser == nil)
    }

    @Test("resolve with browser-prefixed id returns matching target when installed")
    func resolveBrowserPrefixInstalled() {
        // Safari is virtually always installed on macOS test machines
        let resolved = AutoSnapshotTarget.resolve(id: "browser:com.apple.Safari")
        if Browser.safari.isInstalled {
            #expect(resolved.browser == .safari)
            #expect(resolved.label == Browser.safari.displayName)
            #expect(resolved.icon == Browser.safari.iconName)
        } else {
            // Fallback if Safari somehow isn't installed
            #expect(resolved.id == AutoSnapshotTarget.allRunning.id)
        }
    }

    @Test("resolve with browser-prefixed id for uninstalled browser falls back to allRunning")
    func resolveBrowserPrefixNotInstalled() {
        // Use a bundle ID that definitely doesn't exist
        let resolved = AutoSnapshotTarget.resolve(id: "browser:com.nonexistent.browser")
        #expect(resolved.id == AutoSnapshotTarget.allRunning.id)
        #expect(resolved.label == AutoSnapshotTarget.allRunning.label)
    }

    // MARK: - resolve() with old id format (migration)

    @Test("resolve(\"Safari\") migrates to browser:com.apple.Safari target when installed")
    func resolveOldSafariMigration() {
        let resolved = AutoSnapshotTarget.resolve(id: "Safari")
        if Browser.safari.isInstalled {
            #expect(resolved.browser == .safari)
            #expect(resolved.id == "browser:com.apple.Safari")
        } else {
            #expect(resolved.id == AutoSnapshotTarget.allRunning.id)
        }
    }

    @Test("resolve(\"Chrome\") migrates to browser:com.google.Chrome target when installed")
    func resolveOldChromeMigration() {
        let resolved = AutoSnapshotTarget.resolve(id: "Chrome")
        if Browser.chrome.isInstalled {
            #expect(resolved.browser == .chrome)
            #expect(resolved.id == "browser:com.google.Chrome")
        } else {
            #expect(resolved.id == AutoSnapshotTarget.allRunning.id)
        }
    }

    // MARK: - resolve() with unknown id (fallback)

    @Test("resolve with unknown id falls back to .allRunning")
    func resolveUnknownFallsBack() {
        let resolved = AutoSnapshotTarget.resolve(id: "someOldFormatValue")
        #expect(resolved.id == AutoSnapshotTarget.allRunning.id)
        #expect(resolved.label == AutoSnapshotTarget.allRunning.label)
    }

    @Test("resolve with empty string falls back to .allRunning")
    func resolveEmptyString() {
        let resolved = AutoSnapshotTarget.resolve(id: "")
        #expect(resolved.id == AutoSnapshotTarget.allRunning.id)
    }

    @Test("resolve with old bare name that has no migration path falls back to .allRunning")
    func resolveOldBareNameNoMigration() {
        // Only "Safari" and "Chrome" have legacy migration paths.
        // Other bare names like "Firefox" or "Opera" should fall back.
        #expect(AutoSnapshotTarget.resolve(id: "Firefox").id == AutoSnapshotTarget.allRunning.id)
        #expect(AutoSnapshotTarget.resolve(id: "Opera").id == AutoSnapshotTarget.allRunning.id)
        #expect(AutoSnapshotTarget.resolve(id: "Brave").id == AutoSnapshotTarget.allRunning.id)
    }

    // MARK: - installedBrowserTargets

    @Test("installedBrowserTargets does not crash and returns a deterministic result")
    func installedBrowserTargetsDoesNotCrash() {
        // Call it twice — should return the same results (idempotent computed property)
        let first = AutoSnapshotTarget.installedBrowserTargets
        let second = AutoSnapshotTarget.installedBrowserTargets
        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test("installedBrowserTargets only includes installed browsers")
    func installedBrowserTargetsOnlyInstalled() {
        let targets = AutoSnapshotTarget.installedBrowserTargets
        for target in targets {
            guard let browser = target.browser else {
                #expect(Bool(false), "Target \(target.id) has no browser — should not happen")
                continue
            }
            #expect(browser.isInstalled, "Browser \(browser.displayName) should be installed")
        }
    }

    @Test("installedBrowserTargets only includes readable browsers (no Arc, no Firefox)")
    func installedBrowserTargetsExcludesUnscriptable() {
        let targets = AutoSnapshotTarget.installedBrowserTargets
        for target in targets {
            guard let browser = target.browser else {
                continue
            }
            #expect(browser.supportsReadTabs, "Browser \(browser.displayName) should support tab reading")
            #expect(browser != .arc, "Arc should not appear (unscriptable)")
            #expect(browser != .firefox, "Firefox should not appear (unscriptable)")
        }
    }

    @Test("installedBrowserTargets each have correct id format")
    func installedBrowserTargetsIdFormat() {
        let targets = AutoSnapshotTarget.installedBrowserTargets
        for target in targets {
            #expect(target.id.hasPrefix("browser:"), "Target id '\(target.id)' should start with 'browser:'")
            guard let browser = target.browser else { continue }
            #expect(target.id == "browser:\(browser.rawValue)", "Target id should match browser raw value")
        }
    }

    @Test("installedBrowserTargets labels match browser display names")
    func installedBrowserTargetsLabels() {
        let targets = AutoSnapshotTarget.installedBrowserTargets
        for target in targets {
            guard let browser = target.browser else { continue }
            #expect(target.label == browser.displayName)
        }
    }

    @Test("installedBrowserTargets icons match browser icon names")
    func installedBrowserTargetsIcons() {
        let targets = AutoSnapshotTarget.installedBrowserTargets
        for target in targets {
            guard let browser = target.browser else { continue }
            #expect(target.icon == browser.iconName)
        }
    }

    // MARK: - all property

    @Test(".all starts with frontmost and allRunning")
    func allStartsWithConstants() {
        let all = AutoSnapshotTarget.all
        #expect(all.count >= 2)
        #expect(all[0].id == "frontmost")
        #expect(all[1].id == "allRunning")
    }

    @Test(".all contains installedBrowserTargets after constants")
    func allContainsInstalledTargets() {
        let all = AutoSnapshotTarget.all
        let installed = AutoSnapshotTarget.installedBrowserTargets

        // The installed targets should be at the end
        if !installed.isEmpty {
            let lastTargets = Array(all.suffix(installed.count))
            #expect(lastTargets.map(\.id) == installed.map(\.id))
        }
    }

    @Test(".all count equals 2 + installedBrowserTargets.count")
    func allCountIsCorrect() {
        let all = AutoSnapshotTarget.all
        let installed = AutoSnapshotTarget.installedBrowserTargets
        #expect(all.count == 2 + installed.count)
    }

    @Test(".all has no duplicate ids")
    func allHasUniqueIds() {
        let all = AutoSnapshotTarget.all
        let ids = all.map(\.id)
        #expect(ids.count == Set(ids).count, "All ids should be unique")
    }

    // MARK: - Hashable & Identifiable Conformance

    @Test("AutoSnapshotTarget conforms to Hashable — equal targets have same hash")
    func hashableComformance() {
        let t1 = AutoSnapshotTarget.frontmost
        let t2 = AutoSnapshotTarget.resolve(id: "frontmost")

        #expect(t1 == t2)
        #expect(t1.hashValue == t2.hashValue)
    }

    @Test("AutoSnapshotTarget conforms to Hashable — different targets have different hashes")
    func hashableDifferentTargets() {
        let t1 = AutoSnapshotTarget.frontmost
        let t2 = AutoSnapshotTarget.allRunning

        #expect(t1 != t2)
        #expect(t1.hashValue != t2.hashValue)
    }

    @Test("Identifiable conformance — id matches stored id")
    func identifiableConformance() {
        let target = AutoSnapshotTarget.frontmost
        #expect(target.id == "frontmost")
    }

    // MARK: - Sendable (compile-time check)

    @Test("AutoSnapshotTarget conforms to Sendable")
    func sendableConformance() {
        // If this compiles, AutoSnapshotTarget is Sendable
        let targets: [AutoSnapshotTarget] = [.frontmost, .allRunning]
        let _: @Sendable () -> [AutoSnapshotTarget] = { targets }
    }

    // MARK: - Resolve idempotency

    @Test("resolve is idempotent — resolving an already-resolved id returns same target")
    func resolveIsIdempotent() {
        let once = AutoSnapshotTarget.resolve(id: "frontmost")
        let twice = AutoSnapshotTarget.resolve(id: once.id)
        #expect(once == twice)
    }

    // MARK: - Edge Cases

    @Test("resolve with case variation mismatches (ids are case-sensitive)")
    func resolveCaseSensitive() {
        // "Frontmost" != "frontmost" — should fall back to allRunning
        let resolved = AutoSnapshotTarget.resolve(id: "Frontmost")
        #expect(resolved.id == AutoSnapshotTarget.allRunning.id)
    }

    @Test("installedBrowserTargets never returns nil browser for its targets")
    func installedBrowserTargetsBrowserNotNull() {
        let targets = AutoSnapshotTarget.installedBrowserTargets
        for target in targets {
            #expect(target.browser != nil,
                    "Every installed browser target should have a non-nil browser")
        }
    }
}
