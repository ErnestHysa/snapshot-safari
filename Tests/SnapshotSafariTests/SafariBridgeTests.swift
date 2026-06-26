import Testing
import Foundation
@testable import SnapshotSafari

// MARK: - SafariTab Tests

struct SafariTabTests {

    @Test("SafariTab handles null URL (Safari internal pages)")
    func nullURL() throws {
        let json = """
        {"url":null,"title":"Start Page","windowIndex":0,"index":0}
        """
        let data = try #require(json.data(using: .utf8))
        let tab = try JSONDecoder().decode(SafariTab.self, from: data)
        #expect(tab.url == nil)
        #expect(tab.title == "Start Page")
        #expect(tab.windowIndex == 0)
        #expect(tab.index == 0)
    }

    @Test("SafariTab JSON array handles mixed null and real URLs")
    func mixedNullURLs() throws {
        let json = """
        [
            {"url":"https://apple.com","title":"Apple","windowIndex":0,"index":0},
            {"url":null,"title":"Start Page","windowIndex":0,"index":1},
            {"url":"https://github.com","title":"GitHub","windowIndex":0,"index":2}
        ]
        """
        let data = try #require(json.data(using: .utf8))
        let tabs = try JSONDecoder().decode([SafariTab].self, from: data)
        #expect(tabs.count == 3)
        #expect(tabs[0].url == "https://apple.com")
        #expect(tabs[1].url == nil)
        #expect(tabs[2].url == "https://github.com")
    }

    @Test("SafariTab can be created with all properties")
    func createSafariTab() {
        let tab = SafariTab(url: "https://example.com", title: "Example", windowIndex: 0, index: 0)
        #expect(tab.url == "https://example.com")
        #expect(tab.title == "Example")
        #expect(tab.windowIndex == 0)
        #expect(tab.index == 0)
    }

    @Test("SafariTab id is unique per window-index-url combination")
    func uniqueId() {
        let tab1 = SafariTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0)
        let tab2 = SafariTab(url: "https://b.com", title: "B", windowIndex: 0, index: 1)
        let tab3 = SafariTab(url: "https://a.com", title: "A", windowIndex: 1, index: 0)
        #expect(tab1.id != tab2.id)
        #expect(tab1.id != tab3.id)
        #expect(tab2.id != tab3.id)
    }

    @Test("SafariTab equality is based on id")
    func equalityById() {
        let tab1 = SafariTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0)
        let tab2 = SafariTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0)
        #expect(tab1 == tab2)
    }

    @Test("SafariTab inequality detects different index")
    func inequalityByIndex() {
        let tab1 = SafariTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0)
        let tab2 = SafariTab(url: "https://a.com", title: "A", windowIndex: 0, index: 1)
        #expect(tab1 != tab2)
    }

    @Test("SafariTab Codable roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let original = SafariTab(url: "https://swift.org", title: "Swift.org", windowIndex: 2, index: 5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SafariTab.self, from: data)

        #expect(decoded.url == original.url)
        #expect(decoded.title == original.title)
        #expect(decoded.windowIndex == original.windowIndex)
        #expect(decoded.index == original.index)
        #expect(decoded == original)
    }

    @Test("SafariTab Codable handles URLs with special characters")
    func codableSpecialCharacters() throws {
        let original = SafariTab(
            url: "https://example.com/search?q=swift&lang=en#results",
            title: "Search Results: \"Swift\" & <more>",
            windowIndex: 0,
            index: 0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SafariTab.self, from: data)

        #expect(decoded.url == original.url)
        #expect(decoded.title == original.title)
    }

    @Test("SafariTab JSON array roundtrip")
    func jsonArrayRoundtrip() throws {
        let tabs = [
            SafariTab(url: "https://a.com", title: "A", windowIndex: 0, index: 0),
            SafariTab(url: "https://b.com", title: "B", windowIndex: 0, index: 1),
            SafariTab(url: "https://c.com", title: "C", windowIndex: 1, index: 0),
        ]
        let data = try JSONEncoder().encode(tabs)
        let decoded = try JSONDecoder().decode([SafariTab].self, from: data)

        #expect(decoded.count == 3)
        #expect(decoded[0].url == "https://a.com")
        #expect(decoded[1].url == "https://b.com")
        #expect(decoded[2].url == "https://c.com")
    }
}

// MARK: - SafariBridgeError Tests

struct SafariBridgeErrorTests {

    @Test("safariNotRunning has correct description")
    func notRunningDescription() {
        let error = SafariBridgeError.safariNotRunning
        #expect(error.errorDescription == "Safari is not running. Please open Safari first.")
    }

    @Test("permissionDenied has correct description")
    func permissionDeniedDescription() {
        let error = SafariBridgeError.permissionDenied
        #expect(error.errorDescription == "Snapshot Safari doesn't have permission to control Safari. Grant Automation access in System Settings → Privacy & Security → Automation.")
    }

    @Test("scriptError includes detail")
    func scriptErrorDescription() {
        let error = SafariBridgeError.scriptError("Something went wrong")
        #expect(error.errorDescription == "Script error: Something went wrong")
    }

    @Test("invalidOutput has correct description")
    func invalidOutputDescription() {
        let error = SafariBridgeError.invalidOutput
        #expect(error.errorDescription == "Could not parse Safari tab data.")
    }

    @Test("noTabsFound has correct description")
    func noTabsFoundDescription() {
        let error = SafariBridgeError.noTabsFound
        #expect(error.errorDescription == "No open tabs found in Safari.")
    }
}

// MARK: - RestoreMode Tests

struct RestoreModeTests {

    @Test("RestoreMode has two cases")
    func twoCases() {
        #expect(SafariBridge.RestoreMode.allCases.count == 2)
    }

    @Test("RestoreMode raw values match display names")
    func rawValues() {
        #expect(SafariBridge.RestoreMode.newWindow.rawValue == "New Safari Window")
        #expect(SafariBridge.RestoreMode.currentWindow.rawValue == "Current Window (append)")
    }
}

// MARK: - JXA Script Execution Test

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
                {url: "https://example.com/search?q=swift&lang=en", title: "Swift & Friends", windowIndex: 0, index: 0},
                {url: "https://example.com/path%20with%20spaces", title: "Path with spaces", windowIndex: 0, index: 1}
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
        let tabs = try JSONDecoder().decode([SafariTab].self, from: data)
        #expect(tabs.count == 2)
        #expect(tabs[0].url == "https://example.com/search?q=swift&lang=en")
        #expect(tabs[1].url == "https://example.com/path%20with%20spaces")
    }
}
