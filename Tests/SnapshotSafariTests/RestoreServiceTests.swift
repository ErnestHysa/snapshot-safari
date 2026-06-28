import Testing
import Foundation
import SwiftData
@testable import SnapshotSafari

// MARK: - Mock Bridge

/// A controllable mock of BrowserBridge for testing restore logic.
final class MockBridge: BrowserBridge, @unchecked Sendable {
    let browser: Browser

    /// When non-nil, `restoreTabs` returns this count (simulating success).
    var restoreCount: Int?

    /// When non-nil, `restoreTabs` throws this error (simulating failure).
    var restoreError: Error?

    /// Records the last tabs passed to `restoreTabs` for assertions.
    private(set) var lastRestoreTabs: [BrowserTab]?
    private(set) var lastRestoreMode: BrowserRestoreMode?

    init(browser: Browser, restoreCount: Int? = nil, restoreError: Error? = nil) {
        self.browser = browser
        self.restoreCount = restoreCount
        self.restoreError = restoreError
    }

    func readAllTabs() async throws -> [BrowserTab] {
        return []
    }

    func restoreTabs(_ tabs: [BrowserTab], mode: BrowserRestoreMode) async throws -> Int {
        lastRestoreTabs = tabs
        lastRestoreMode = mode
        if let error = restoreError {
            throw error
        }
        return restoreCount ?? tabs.count
    }
}

// MARK: - Helpers

/// Creates a simple BrowserBridge error for testing.
func makeTestError(_ message: String) -> Error {
    BrowserBridgeError.scriptError(message)
}

// MARK: - RestorePartialFailure Tests

struct RestorePartialFailureTests {

    @Test("errorDescription formats single tab + single browser failure")
    func singleTabSingleFailure() {
        let error = makeTestError("Chrome is not running")
        let failure = SnapshotService.RestorePartialFailure(
            totalRestored: 1,
            failedBrowsers: [(.chrome, error)]
        )
        let desc = failure.errorDescription
        #expect(desc != nil)
        #expect(desc!.contains("Restored 1 tab"))
        #expect(desc!.contains("Chrome could not be restored"))
        #expect(desc!.contains("Chrome is not running"))
    }

    @Test("errorDescription formats multiple tabs + single browser failure")
    func multipleTabsSingleFailure() {
        let error = makeTestError("Safari is not running")
        let failure = SnapshotService.RestorePartialFailure(
            totalRestored: 5,
            failedBrowsers: [(.safari, error)]
        )
        let desc = failure.errorDescription
        #expect(desc != nil)
        #expect(desc!.contains("Restored 5 tabs"))
        #expect(desc!.contains("Safari could not be restored"))
    }

    @Test("errorDescription formats multiple browser failures joined with semicolons")
    func multipleBrowserFailures() {
        let failure = SnapshotService.RestorePartialFailure(
            totalRestored: 3,
            failedBrowsers: [
                (.chrome, makeTestError("Chrome not running")),
                (.safari, makeTestError("Permission denied")),
            ]
        )
        let desc = failure.errorDescription
        #expect(desc != nil)
        // scriptError wraps with "Script error: " prefix
        #expect(desc!.contains("Chrome could not be restored — Script error: Chrome not running"))
        #expect(desc!.contains("Safari could not be restored — Script error: Permission denied"))
        // Separated by "; "
        #expect(desc!.contains("; "))
    }

    @Test("errorDescription uses 'tab' singular when totalRestored is 1")
    func singularTabLabel() {
        let failure = SnapshotService.RestorePartialFailure(
            totalRestored: 1,
            failedBrowsers: [(.chrome, makeTestError("err"))]
        )
        #expect(failure.errorDescription?.contains("Restored 1 tab,") == true)
    }

    @Test("errorDescription uses 'tabs' plural when totalRestored > 1")
    func pluralTabLabel() {
        let failure = SnapshotService.RestorePartialFailure(
            totalRestored: 2,
            failedBrowsers: [(.chrome, makeTestError("err"))]
        )
        #expect(failure.errorDescription?.contains("Restored 2 tabs,") == true)
    }

    @Test("errorDescription uses 'tabs' plural when totalRestored is 0")
    func zeroTabLabel() {
        let failure = SnapshotService.RestorePartialFailure(
            totalRestored: 0,
            failedBrowsers: [(.chrome, makeTestError("err"))]
        )
        #expect(failure.errorDescription?.contains("Restored 0 tabs,") == true)
    }

    @Test("totalRestored and failedBrowsers are stored correctly")
    func storedProperties() {
        let browsers: [(Browser, Error)] = [(.chrome, makeTestError("test"))]
        let failure = SnapshotService.RestorePartialFailure(
            totalRestored: 7,
            failedBrowsers: browsers
        )
        #expect(failure.totalRestored == 7)
        #expect(failure.failedBrowsers.count == 1)
        #expect(failure.failedBrowsers[0].0 == .chrome)
    }
}

// MARK: - restoreGroups Tests

@MainActor
struct RestoreGroupsTests {

    // MARK: - Empty / Invalid Groups

    @Test("restoreGroups with empty groups throws noTabsFound")
    func emptyGroupsThrowsNoTabsFound() async {
        let container = createTestContainer()
        let service = SnapshotService(modelContext: container.mainContext)

        do {
            _ = try await service.restoreGroups([:], mode: .newWindow)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let bridgeError as BrowserBridgeError {
            #expect(bridgeError.errorDescription == BrowserBridgeError.noTabsFound.errorDescription)
        } catch {
            #expect(Bool(false), "Expected BrowserBridgeError")
        }
    }

    @Test("restoreGroups with groups only containing invalid browserIds throws noTabsFound")
    func invalidBrowserIdsThrowsNoTabsFound() async {
        let container = createTestContainer()
        let service = SnapshotService(modelContext: container.mainContext)

        let tabs = [TabEntry(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: "com.nonexistent.Browser")]
        let groups = Dictionary(grouping: tabs) { $0.browserId }

        do {
            _ = try await service.restoreGroups(groups, mode: .newWindow)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let bridgeError as BrowserBridgeError {
            #expect(bridgeError.errorDescription == BrowserBridgeError.noTabsFound.errorDescription)
        } catch {
            #expect(Bool(false), "Expected BrowserBridgeError")
        }
    }

    // MARK: - All Success

    @Test("restoreGroups returns total count when all bridges succeed")
    func allSuccessReturnsTotalCount() async throws {
        let container = createTestContainer()

        // Create a service with mock bridges that succeed
        let service = SnapshotService(modelContext: container.mainContext) { browser in
            MockBridge(browser: browser, restoreCount: 3)
        }

        let tabs = [
            TabEntry(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: Browser.safari.rawValue),
            TabEntry(url: "https://b.com", title: "B", windowIndex: 0, index: 0, browserId: Browser.chrome.rawValue),
        ]
        let groups = Dictionary(grouping: tabs) { $0.browserId }

        let count = try await service.restoreGroups(groups, mode: .currentWindow)
        // 2 groups × 3 each = 6 — but each mock returns 3 regardless of tab count
        // Each group has 1 tab, but MockBridge returns restoreCount (3)
        #expect(count == 6)
    }

    @Test("restoreGroups passes tabs and mode to each bridge")
    func allSuccessPassesCorrectTabs() async throws {
        let container = createTestContainer()
        let safariMock = MockBridge(browser: .safari, restoreCount: 1)
        let chromeMock = MockBridge(browser: .chrome, restoreCount: 2)

        let providerMap: [Browser: MockBridge] = [
            .safari: safariMock,
            .chrome: chromeMock,
        ]

        let service = SnapshotService(modelContext: container.mainContext) { browser in
            providerMap[browser] ?? MockBridge(browser: browser, restoreCount: 0)
        }

        let tabs = [
            TabEntry(url: "https://safari.com", title: "Safari Tab", windowIndex: 0, index: 0, browserId: Browser.safari.rawValue),
            TabEntry(url: "https://chrome1.com", title: "Chrome 1", windowIndex: 0, index: 0, browserId: Browser.chrome.rawValue),
            TabEntry(url: "https://chrome2.com", title: "Chrome 2", windowIndex: 0, index: 0, browserId: Browser.chrome.rawValue),
        ]
        let groups = Dictionary(grouping: tabs) { $0.browserId }

        let count = try await service.restoreGroups(groups, mode: .newWindow)
        #expect(count == 3) // 1 (safari returns 1) + 2 (chrome returns 2)

        // Safari bridge received 1 tab
        #expect(safariMock.lastRestoreTabs?.count == 1)
        #expect(safariMock.lastRestoreTabs?.first?.url == "https://safari.com")
        #expect(safariMock.lastRestoreMode == .newWindow)

        // Chrome bridge received 2 tabs
        #expect(chromeMock.lastRestoreTabs?.count == 2)
        #expect(chromeMock.lastRestoreMode == .newWindow)
    }

    // MARK: - Total Failure

    @Test("restoreGroups throws an error when all bridges fail")
    func allFailThrowsAnError() async {
        let container = createTestContainer()

        let service = SnapshotService(modelContext: container.mainContext) { browser in
            MockBridge(
                browser: browser,
                restoreError: makeTestError("\(browser.shortName) failed")
            )
        }

        let tabs = [
            TabEntry(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: Browser.safari.rawValue),
            TabEntry(url: "https://b.com", title: "B", windowIndex: 0, index: 0, browserId: Browser.chrome.rawValue),
        ]
        let groups = Dictionary(grouping: tabs) { $0.browserId }

        do {
            _ = try await service.restoreGroups(groups, mode: .newWindow)
            #expect(Bool(false), "Expected error to be thrown")
        } catch {
            // An error should be thrown — which one depends on dictionary iteration order
            let nsError = error as NSError
            let isFromSafariOrChrome = nsError.localizedDescription.contains("Safari") || nsError.localizedDescription.contains("Chrome")
            #expect(isFromSafariOrChrome, "Error should mention a failing browser")
        }
    }

    // MARK: - Partial Failure

    @Test("restoreGroups throws RestorePartialFailure when some succeed and some fail")
    func partialFailureThrowsRestorePartialFailure() async {
        let container = createTestContainer()

        let service = SnapshotService(modelContext: container.mainContext) { browser in
            if browser == .safari {
                return MockBridge(browser: browser, restoreCount: 3)
            } else {
                return MockBridge(browser: browser, restoreError: makeTestError("Chrome not running"))
            }
        }

        let tabs = [
            TabEntry(url: "https://safari.com", title: "S", windowIndex: 0, index: 0, browserId: Browser.safari.rawValue),
            TabEntry(url: "https://chrome.com", title: "C", windowIndex: 0, index: 0, browserId: Browser.chrome.rawValue),
        ]
        let groups = Dictionary(grouping: tabs) { $0.browserId }

        do {
            _ = try await service.restoreGroups(groups, mode: .newWindow)
            #expect(Bool(false), "Expected RestorePartialFailure")
        } catch let partial as SnapshotService.RestorePartialFailure {
            #expect(partial.totalRestored == 3)
            #expect(partial.failedBrowsers.count == 1)
            #expect(partial.failedBrowsers[0].0 == .chrome)
            #expect(partial.errorDescription?.contains("Restored 3 tabs") == true)
            #expect(partial.errorDescription?.contains("Chrome could not be restored") == true)
        } catch {
            #expect(Bool(false), "Expected RestorePartialFailure, got \(error)")
        }
    }

    @Test("restoreGroups RestorePartialFailure includes multiple failed browsers")
    func partialFailureMultipleBrowsers() async {
        let container = createTestContainer()

        let service = SnapshotService(modelContext: container.mainContext) { browser in
            if browser == .safari {
                return MockBridge(browser: browser, restoreCount: 2)
            } else {
                return MockBridge(browser: browser, restoreError: makeTestError("\(browser.shortName) failed"))
            }
        }

        let tabs = [
            TabEntry(url: "https://safari.com", title: "S", windowIndex: 0, index: 0, browserId: Browser.safari.rawValue),
            TabEntry(url: "https://chrome.com", title: "C1", windowIndex: 0, index: 0, browserId: Browser.chrome.rawValue),
            TabEntry(url: "https://brave.com", title: "B", windowIndex: 0, index: 0, browserId: Browser.brave.rawValue),
        ]
        let groups = Dictionary(grouping: tabs) { $0.browserId }

        do {
            _ = try await service.restoreGroups(groups, mode: .currentWindow)
            #expect(Bool(false), "Expected RestorePartialFailure")
        } catch let partial as SnapshotService.RestorePartialFailure {
            #expect(partial.totalRestored == 2)
            #expect(partial.failedBrowsers.count == 2)
            let failedNames = Set(partial.failedBrowsers.map { $0.0 })
            #expect(failedNames.contains(.chrome))
            #expect(failedNames.contains(.brave))
        } catch {
            #expect(Bool(false), "Expected RestorePartialFailure")
        }
    }

    @Test("restoreGroups partial failure preserves error details per browser")
    func partialFailurePreservesErrorDetails() async {
        let container = createTestContainer()
        let chromeError = makeTestError("Chrome not running")

        let service = SnapshotService(modelContext: container.mainContext) { browser in
            if browser == .safari {
                return MockBridge(browser: browser, restoreCount: 1)
            } else {
                return MockBridge(browser: browser, restoreError: chromeError)
            }
        }

        let tabs = [
            TabEntry(url: "https://safari.com", title: "S", windowIndex: 0, index: 0, browserId: Browser.safari.rawValue),
            TabEntry(url: "https://chrome.com", title: "C", windowIndex: 0, index: 0, browserId: Browser.chrome.rawValue),
        ]
        let groups = Dictionary(grouping: tabs) { $0.browserId }

        do {
            _ = try await service.restoreGroups(groups, mode: .newWindow)
            #expect(Bool(false), "Expected RestorePartialFailure")
        } catch let partial as SnapshotService.RestorePartialFailure {
            #expect(partial.failedBrowsers[0].1 is BrowserBridgeError)
            if let bridgeError = partial.failedBrowsers[0].1 as? BrowserBridgeError {
                // scriptError wraps with "Script error: " prefix
                #expect(bridgeError.errorDescription == "Script error: Chrome not running")
            }
        } catch {
            #expect(Bool(false), "Expected RestorePartialFailure, got \(error)")
        }
    }

    // MARK: - Unknown / Skipped BrowserIds

    @Test("restoreGroups skips browserIds that don't match any Browser case")
    func skipsUnknownBrowserIds() async throws {
        let container = createTestContainer()

        let safariMock = MockBridge(browser: .safari, restoreCount: 2)
        let service = SnapshotService(modelContext: container.mainContext) { _ in
            safariMock
        }

        let tabs = [
            TabEntry(url: "https://safari.com", title: "S", windowIndex: 0, index: 0, browserId: Browser.safari.rawValue),
            TabEntry(url: "https://unknown.com", title: "U", windowIndex: 0, index: 0, browserId: "com.unknown.whatever"),
        ]
        let groups = Dictionary(grouping: tabs) { $0.browserId }

        let count = try await service.restoreGroups(groups, mode: .newWindow)
        // Unknown browserId group is skipped; Safari tab count returned by mock is 2
        #expect(count == 2)
        #expect(safariMock.lastRestoreTabs?.count == 1) // only 1 tab in the Safari group
    }

    // MARK: - Mode Propagation

    @Test("restoreGroups passes newWindow mode to bridges")
    func passesNewWindowMode() async throws {
        let container = createTestContainer()
        let mock = MockBridge(browser: .safari, restoreCount: 1)
        let service = SnapshotService(modelContext: container.mainContext) { _ in mock }

        let tabs = [TabEntry(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: Browser.safari.rawValue)]
        _ = try await service.restoreGroups(Dictionary(grouping: tabs) { $0.browserId }, mode: .newWindow)

        #expect(mock.lastRestoreMode == .newWindow)
    }

    @Test("restoreGroups passes currentWindow mode to bridges")
    func passesCurrentWindowMode() async throws {
        let container = createTestContainer()
        let mock = MockBridge(browser: .safari, restoreCount: 1)
        let service = SnapshotService(modelContext: container.mainContext) { _ in mock }

        let tabs = [TabEntry(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: Browser.safari.rawValue)]
        _ = try await service.restoreGroups(Dictionary(grouping: tabs) { $0.browserId }, mode: .currentWindow)

        #expect(mock.lastRestoreMode == .currentWindow)
    }
}
