import Testing
import Foundation
@testable import SnapshotSafari

// MARK: - BrowserTab Tests

struct BrowserTabTests {

    @Test("BrowserTab handles null URL (browser internal pages)")
    func nullURL() throws {
        let json = """
        {"url":null,"title":"Start Page","windowIndex":0,"index":0,"browserId":"com.apple.Safari"}
        """
        let data = try #require(json.data(using: .utf8))
        let tab = try JSONDecoder().decode(BrowserTab.self, from: data)
        #expect(tab.url == nil)
        #expect(tab.title == "Start Page")
        #expect(tab.windowIndex == 0)
        #expect(tab.index == 0)
        #expect(tab.browserId == "com.apple.Safari")
    }

    @Test("BrowserTab JSON array handles mixed null and real URLs")
    func mixedNullURLs() throws {
        let json = """
        [
            {"url":"https://apple.com","title":"Apple","windowIndex":0,"index":0,"browserId":"com.apple.Safari"},
            {"url":null,"title":"Start Page","windowIndex":0,"index":1,"browserId":"com.apple.Safari"},
            {"url":"https://github.com","title":"GitHub","windowIndex":0,"index":2,"browserId":"com.apple.Safari"}
        ]
        """
        let data = try #require(json.data(using: .utf8))
        let tabs = try JSONDecoder().decode([BrowserTab].self, from: data)
        #expect(tabs.count == 3)
        #expect(tabs[0].url == "https://apple.com")
        #expect(tabs[1].url == nil)
        #expect(tabs[2].url == "https://github.com")
    }

    @Test("BrowserTab can be created with all properties")
    func createBrowserTab() {
        let tab = BrowserTab(url: "https://example.com", title: "Example", windowIndex: 0, index: 0, browserId: "com.apple.Safari")
        #expect(tab.url == "https://example.com")
        #expect(tab.title == "Example")
        #expect(tab.windowIndex == 0)
        #expect(tab.index == 0)
        #expect(tab.browserId == "com.apple.Safari")
    }

    @Test("BrowserTab id is unique per browser-window-index-url combination")
    func uniqueId() {
        let tab1 = BrowserTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: "com.apple.Safari")
        let tab2 = BrowserTab(url: "https://b.com", title: "B", windowIndex: 0, index: 1, browserId: "com.apple.Safari")
        let tab3 = BrowserTab(url: "https://a.com", title: "A", windowIndex: 1, index: 0, browserId: "com.apple.Safari")
        let tab4 = BrowserTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: "com.google.Chrome")
        #expect(tab1.id != tab2.id)
        #expect(tab1.id != tab3.id)
        #expect(tab1.id != tab4.id)
    }

    @Test("BrowserTab equality is based on id")
    func equalityById() {
        let tab1 = BrowserTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: "com.apple.Safari")
        let tab2 = BrowserTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: "com.apple.Safari")
        #expect(tab1 == tab2)
    }

    @Test("BrowserTab inequality detects different index")
    func inequalityByIndex() {
        let tab1 = BrowserTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: "com.apple.Safari")
        let tab2 = BrowserTab(url: "https://a.com", title: "A", windowIndex: 0, index: 1, browserId: "com.apple.Safari")
        #expect(tab1 != tab2)
    }

    @Test("BrowserTab inequality detects different browser")
    func inequalityByBrowser() {
        let tab1 = BrowserTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: "com.apple.Safari")
        let tab2 = BrowserTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: "com.google.Chrome")
        #expect(tab1 != tab2)
    }

    @Test("BrowserTab Codable roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let original = BrowserTab(url: "https://swift.org", title: "Swift.org", windowIndex: 2, index: 5, browserId: "com.apple.Safari")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: data)

        #expect(decoded.url == original.url)
        #expect(decoded.title == original.title)
        #expect(decoded.windowIndex == original.windowIndex)
        #expect(decoded.index == original.index)
        #expect(decoded.browserId == original.browserId)
        #expect(decoded == original)
    }

    @Test("BrowserTab Codable handles URLs with special characters")
    func codableSpecialCharacters() throws {
        let original = BrowserTab(
            url: "https://example.com/search?q=swift&lang=en#results",
            title: "Search Results: \"Swift\" & <more>",
            windowIndex: 0,
            index: 0,
            browserId: "com.apple.Safari"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: data)

        #expect(decoded.url == original.url)
        #expect(decoded.title == original.title)
    }

    @Test("BrowserTab JSON array roundtrip")
    func jsonArrayRoundtrip() throws {
        let tabs = [
            BrowserTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0, browserId: "com.apple.Safari"),
            BrowserTab(url: "https://b.com", title: "B", windowIndex: 0, index: 1, browserId: "com.apple.Safari"),
            BrowserTab(url: "https://c.com", title: "C", windowIndex: 1, index: 0, browserId: "com.google.Chrome"),
        ]
        let data = try JSONEncoder().encode(tabs)
        let decoded = try JSONDecoder().decode([BrowserTab].self, from: data)

        #expect(decoded.count == 3)
        #expect(decoded[0].url == "https://a.com")
        #expect(decoded[1].url == "https://b.com")
        #expect(decoded[2].url == "https://c.com")
        #expect(decoded[0].browserId == "com.apple.Safari")
        #expect(decoded[2].browserId == "com.google.Chrome")
    }
}

// MARK: - BrowserBridgeError Tests

struct BrowserBridgeErrorTests {

    @Test("browserNotRunning has correct description")
    func notRunningDescription() {
        let error = BrowserBridgeError.browserNotRunning(.safari)
        #expect(error.errorDescription == "Safari is not running. Please open Safari first.")
    }

    @Test("browserNotRunning works for Chrome")
    func chromeNotRunningDescription() {
        let error = BrowserBridgeError.browserNotRunning(.chrome)
        #expect(error.errorDescription == "Google Chrome is not running. Please open Chrome first.")
    }

    @Test("permissionDenied has correct description")
    func permissionDeniedDescription() {
        let error = BrowserBridgeError.permissionDenied(.safari)
        #expect(error.errorDescription == "Snapshot Safari doesn't have permission to control Safari. Grant Automation access in System Settings → Privacy & Security → Automation.")
    }

    @Test("permissionDenied works for Chrome")
    func chromePermissionDeniedDescription() {
        let error = BrowserBridgeError.permissionDenied(.chrome)
        #expect(error.errorDescription == "Snapshot Safari doesn't have permission to control Google Chrome. Grant Automation access in System Settings → Privacy & Security → Automation.")
    }

    @Test("scriptError includes detail")
    func scriptErrorDescription() {
        let error = BrowserBridgeError.scriptError("Something went wrong")
        #expect(error.errorDescription == "Script error: Something went wrong")
    }

    @Test("invalidOutput has correct description")
    func invalidOutputDescription() {
        let error = BrowserBridgeError.invalidOutput
        #expect(error.errorDescription == "Could not parse browser tab data.")
    }

    @Test("noTabsFound has correct description")
    func noTabsFoundDescription() {
        let error = BrowserBridgeError.noTabsFound
        #expect(error.errorDescription == "No open tabs found.")
    }

    @Test("unsupportedOperation includes detail")
    func unsupportedOperationDescription() {
        let error = BrowserBridgeError.unsupportedOperation("Arc does not support tab reading.")
        #expect(error.errorDescription == "Arc does not support tab reading.")
    }
}

// MARK: - BrowserRestoreMode Tests

struct BrowserRestoreModeTests {

    @Test("BrowserRestoreMode has two cases")
    func twoCases() {
        #expect(BrowserRestoreMode.allCases.count == 2)
    }

    @Test("BrowserRestoreMode raw values match display names")
    func rawValues() {
        #expect(BrowserRestoreMode.newWindow.rawValue == "New Window")
        #expect(BrowserRestoreMode.currentWindow.rawValue == "Current Window (append)")
    }
}

// MARK: - JXA Script Execution Tests

struct JXAExecutionTests {

    @Test("osascript can execute a simple JXA script")
    func simpleJXA() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", "function run() { return 'Hello from JXA'; }"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(output == "Hello from JXA")
    }

    @Test("osascript can parse and stringify JSON")
    func jxaJSON() throws {
        let script = """
        function run() {
            var obj = {url: "https://apple.com", title: "Apple", index: 0};
            return JSON.stringify(obj);
        }
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(output != nil)
        let data = try #require(output?.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["url"] as? String == "https://apple.com")
        #expect(decoded?["title"] as? String == "Apple")
        #expect(decoded?["index"] as? Int == 0)
    }

    @Test("osascript returns error for invalid JXA")
    func invalidJXA() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", "function run() { return broken.syntax.!!!; }"]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(process.terminationStatus != 0)
        #expect(errorOutput?.isEmpty == false)
    }

    @Test("osascript returns an empty array JSON for no tabs")
    func emptyTabsJSON() throws {
        let script = "function run() { return JSON.stringify([]); }"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(output == "[]")
    }

    @Test("osascript encodes special characters in JSON properly")
    func specialCharsJSON() throws {
        let script = """
        function run() {
            var tabs = [
                {url: "https://example.com/search?q=swift&lang=en", title: "Swift & Friends", windowIndex: 0, index: 0, browserId: "com.apple.Safari"},
                {url: "https://example.com/path%20with%20spaces", title: "Path with spaces", windowIndex: 0, index: 1, browserId: "com.apple.Safari"}
            ];
            return JSON.stringify(tabs);
        }
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(process.terminationStatus == 0)
        let data = try #require(output?.data(using: .utf8))
        let tabs = try JSONDecoder().decode([BrowserTab].self, from: data)
        #expect(tabs.count == 2)
        #expect(tabs[0].url == "https://example.com/search?q=swift&lang=en")
        #expect(tabs[1].url == "https://example.com/path%20with%20spaces")
        #expect(tabs[0].browserId == "com.apple.Safari")
    }
}
