import Foundation
import AppKit
import SwiftUI

// MARK: - Browser Engine

enum BrowserEngine: String, Codable, CaseIterable {
    case webkit
    case chromium
    case unscriptable
}

// MARK: - Browser

/// Represents a supported macOS browser.
/// Raw value is the bundle identifier so we can init from `NSRunningApplication.bundleIdentifier`.
enum Browser: String, CaseIterable, Identifiable, Codable {
    case safari  = "com.apple.Safari"
    case chrome  = "com.google.Chrome"
    case brave   = "com.brave.Browser"
    case edge    = "com.microsoft.edgemac"
    case opera   = "com.operasoftware.Opera"
    case vivaldi = "com.vivaldi.Vivaldi"
    case orion   = "com.kagi.kagimacOS"
    case arc     = "company.thebrowser.Browser"
    case firefox = "org.mozilla.firefox"

    var id: String { rawValue }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .safari:  return "Safari"
        case .chrome:  return "Google Chrome"
        case .brave:   return "Brave Browser"
        case .edge:    return "Microsoft Edge"
        case .opera:   return "Opera"
        case .vivaldi: return "Vivaldi"
        case .orion:   return "Orion"
        case .arc:     return "Arc"
        case .firefox: return "Firefox"
        }
    }

    /// Short label for UI badges and compact displays.
    var shortName: String {
        switch self {
        case .safari:  return "Safari"
        case .chrome:  return "Chrome"
        case .brave:   return "Brave"
        case .edge:    return "Edge"
        case .opera:   return "Opera"
        case .vivaldi: return "Vivaldi"
        case .orion:   return "Orion"
        case .arc:     return "Arc"
        case .firefox: return "Firefox"
        }
    }

    /// The application name used inside JXA scripts: `Application('Safari')`, etc.
    var jxaAppName: String {
        switch self {
        case .safari:  return "Safari"
        case .chrome:  return "Google Chrome"
        case .brave:   return "Brave Browser"
        case .edge:    return "Microsoft Edge"
        case .opera:   return "Opera"
        case .vivaldi: return "Vivaldi"
        case .orion:   return "Orion"
        case .arc:     return "Arc"
        case .firefox: return "Firefox"
        }
    }

    // MARK: - Engine

    var engine: BrowserEngine {
        switch self {
        case .safari, .orion:
            return .webkit
        case .chrome, .brave, .edge, .opera, .vivaldi:
            return .chromium
        case .arc, .firefox:
            return .unscriptable
        }
    }

    /// Whether this browser's tabs can be read via JXA/AppleEvents.
    var supportsReadTabs: Bool {
        engine != .unscriptable
    }

    // MARK: - SF Symbol

    var iconName: String {
        switch self {
        case .safari:  return "safari"
        case .chrome:  return "circle.dotted"
        case .brave:   return "shield.righthalf.filled"
        case .edge:    return "wave.3.right"
        case .opera:   return "o.circle"
        case .vivaldi: return "v.circle"
        case .orion:   return "scope"
        case .arc:     return "arkit"
        case .firefox: return "flame"
        }
    }

    // MARK: - Brand Color

    /// The browser's distinctive brand color for tinted badge backgrounds.
    var brandColor: Color {
        switch self {
        case .safari:  return .blue
        case .chrome:  return .green
        case .brave:   return .orange
        case .edge:    return .teal
        case .opera:   return .red
        case .vivaldi: return .pink
        case .orion:   return .purple
        case .arc:     return .indigo
        case .firefox: return .orange
        }
    }

    // MARK: - Runtime State

    /// Whether the browser is currently running.
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
    }

    /// Whether the browser is installed (app bundle exists on disk).
    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil
    }

    // MARK: - Static Helpers

    /// All browsers that are currently running.
    static var runningBrowsers: [Browser] {
        allCases.filter { $0.isRunning }
    }

    /// All browsers that are running AND support tab reading.
    static var readableRunningBrowsers: [Browser] {
        allCases.filter { $0.isRunning && $0.supportsReadTabs }
    }

    /// All browsers installed on this Mac.
    static var installedBrowsers: [Browser] {
        allCases.filter { $0.isInstalled }
    }

    /// The currently frontmost browser, if it's one we support.
    static var frontmostBrowser: Browser? {
        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return nil
        }
        return Browser(rawValue: bundleId)
    }

    /// Activate (bring to foreground) this browser.
    func activate() {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: rawValue
        ).first else { return }
        app.activate(options: .activateIgnoringOtherApps)
    }
}
