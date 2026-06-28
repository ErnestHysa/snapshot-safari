# 🦁 Snapshot Safari — Architecture Document

> **Version:** 1.1.0
> **Bundle ID:** `com.ernest.snapshot-safari`
> **Distribution:** `.dmg` via ad-hoc signing (public) or Developer ID + notarization (signed)

---

## 1. Product Overview

Snapshot Safari is a native macOS application that captures all open browser tabs into named
**snapshots**, allowing users to close tabs to free RAM and restore them later — individually
or all at once. It supports **9 browsers** (Safari, Chrome, Brave, Edge, Opera, Vivaldi,
Orion, Arc, Firefox), selective tab restore, snapshot comparison/diffing, auto-snapshots
on a schedule, JSON export/import, soft-delete with trash recovery, and iCloud sync (requires
Apple Developer Program).

### Core Flow

```
Browser(s) (many tabs open)
      │
      ▼  User clicks "Take Snapshot" (⌘N = frontmost, ⌘⇧N = all running)
┌─────────────────┐
│ BrowserBridge    │── Reads tabs via JXA (WebKit or Chromium engine)
│ (OSAScript/JXA) │── Returns [{url, title, windowIndex, index, browserId}]
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   SwiftData DB   │── Stores snapshot + browser-tagged tabs (local SQLite)
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│  SwiftUI List View   │── Displays snapshots with browser badges + favicons
└────────┬────────────┘
         │
    User clicks "Restore"
         │
         ▼
┌─────────────────┐
│ BrowserBridge    │── Opens tabs in their original browsers (or chosen target)
└─────────────────┘
```

---

## 2. Technology Stack

| Layer            | Technology                          | Rationale                                    |
| ---------------- | ----------------------------------- | -------------------------------------------- |
| Language         | Swift 6                             | Full strict concurrency, modern macOS        |
| UI Framework     | SwiftUI                             | Declarative, dark/light, NavigationSplitView |
| Data Persistence | SwiftData (`.sqlite` backing store) | Apple-native ORM, `#Predicate`, migrations   |
| Browser Bridge   | JXA via `OSAScript`                 | In-process, returns structured JSON, works across WebKit + Chromium |
| Auto-Updates     | Sparkle 2.x                         | Standard Mac auto-update framework           |
| iCloud Sync      | CloudKit (via SwiftData)            | Optional, requires Developer ID              |
| Favicons         | Google Favicons API                 | `https://www.google.com/s2/favicons?domain=` |
| Build System     | Swift Package Manager               | Standard Apple toolchain, no Xcode required  |
| Distribution     | Ad-hoc signed `.dmg`                | GitHub Releases + Sparkle appcast            |

---

## 3. Project Structure

```
Snapshot-Safari/
├── Package.swift                                 # SPM manifest (Swift 6, macOS 15+)
├── appcast.xml                                   # Sparkle update feed
├── Sources/SnapshotSafari/
│   ├── SnapshotSafariApp.swift                   # App entry, commands, CloudKit init
│   ├── Info.plist                                # Bundle metadata, Sparkle keys
│   ├── Resources/
│   │   ├── Assets.xcassets                       # App icon, colors
│   │   ├── AppIcon.icns                          # Compiled app icon
│   │   └── Entitlements/
│   │       ├── SnapshotSafari.entitlements       # Public build (no iCloud)
│   │       └── SnapshotSafari.entitlements.dev   # Developer build (with iCloud)
│   ├── Models/
│   │   ├── Browser.swift                         # 9-browser enum: bundle IDs, brand colors, runtime state
│   │   ├── Snapshot.swift                        # SwiftData model: snapshot with tabs
│   │   ├── TabEntry.swift                        # SwiftData model: browser-tagged tab
│   │   ├── SnapshotDiff.swift                    # Diff computation between snapshots
│   │   └── SnapshotExport.swift                  # Codable export/import format
│   ├── Services/
│   │   ├── BrowserBridge.swift                   # Protocol + WebKit/Chromium/Unscriptable bridges
│   │   ├── SnapshotService.swift                 # Multi-browser capture/restore, CRUD, search, trash
│   │   ├── AutoSnapshotManager.swift             # Dynamic browser-target auto-snapshot loop
│   │   ├── PermissionsService.swift              # Per-browser Automation permission check
│   │   ├── SyncService.swift                     # iCloud sync + runtime entitlement check
│   │   ├── FaviconService.swift                  # Cached favicon fetching
│   │   └── SparkleUpdater.swift                  # Auto-update orchestration
│   ├── ViewModels/
│   │   └── SnapshotListViewModel.swift           # Observable state: filters, capture, restore, export
│   ├── Utilities/
│   │   └── AutoNamer.swift                       # Smart snapshot name generation with browser names
│   └── Views/
│       ├── ContentView.swift                     # Root: NavigationSplitView + toolbar with capture menu
│       ├── SnapshotListView.swift                # Sidebar list with browser filter picker
│       ├── SnapshotCard.swift                    # List item with Capture All badge + browser pills
│       ├── SnapshotDetailView.swift              # Tab list + browser-aware restore/export/delete
│       ├── TabRow.swift                          # Individual tab row with colored browser badge
│       ├── RestoreOptionsSheet.swift             # Restore mode + browser target picker
│       ├── CompareSnapshotsView.swift            # Visual diff display
│       ├── TrashView.swift                       # Recently deleted snapshots
│       ├── SettingsView.swift                    # Multi-browser permissions + auto-snapshot target
│       └── WelcomeView.swift                     # First-launch onboarding
├── Scripts/
│   ├── build-app.sh                              # swift build → .app bundle → codesign
│   ├── generate-icon.py                          # SVG → PNGs → AppIcon.icns
│   └── release/
│       ├── build-release.sh                      # swift test + build-app.sh + stage
│       ├── sign-app.sh                           # Developer ID sign + Hardened Runtime
│       ├── make-dmg.sh                           # Compressed read-only DMG via hdiutil
│       ├── notarize-dmg.sh                       # notarytool submit --wait
│       ├── staple-and-verify.sh                  # stapler staple + spctl + codesign
│       └── verify-release.sh                     # Bundle/codesign/entitlements/plist checks
└── Tests/SnapshotSafariTests/
    ├── BrowserBridgeTests.swift                   # BrowserTab, BrowserBridgeError, JXA execution
    ├── SnapshotServiceTests.swift                 # CRUD, search, trash, cleanup
    ├── RestoreServiceTests.swift                  # RestorePartialFailure, restoreGroups with MockBridge
    ├── AutoSnapshotTargetTests.swift              # Dynamic target resolution, migration
    ├── SnapshotDiffTests.swift                    # Diff algorithm
    ├── SnapshotExportTests.swift                  # Export/import
    ├── SyncServiceTests.swift                     # Sync state + entitlements
    ├── AutoNamerTests.swift                       # Naming
    ├── PermissionsServiceProbeTests.swift         # TCC permission probe
    └── SettingsTabTests.swift                     # Settings UI
```

---

## 4. Data Model

### 4.1 Browser (Enum)

```swift
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

    var engine: BrowserEngine          // .webkit, .chromium, .unscriptable
    var supportsReadTabs: Bool
    var iconName: String               // SF Symbol
    var brandColor: Color              // Tinted badge background
    var isRunning: Bool
    var isInstalled: Bool
}
```

### 4.2 Snapshot

```swift
@Model
final class Snapshot {
    var id: UUID
    var name: String                    // Auto-named with browser name
    var createdAt: Date
    var updatedAt: Date
    var isTrashed: Bool                 // Soft-delete flag
    var deletedAt: Date?                // Timestamp for 30-day auto-purge
    var isAutoSnapshot: Bool
    @Relationship(deleteRule: .cascade) var tabs: [TabEntry]
    var tabCount: Int { tabs.count }
}
```

### 4.3 TabEntry

```swift
@Model
final class TabEntry {
    var id: UUID
    var url: String
    var domain: String
    var title: String
    var windowIndex: Int
    var index: Int
    var browserId: String               // Browser.rawValue (bundle identifier)
    var browser: Browser?               // Computed from browserId
    var snapshot: Snapshot?
}
```

### 4.4 SnapshotDiff / SnapshotExport

Unchanged from 1.0.x — pure value types for comparison and JSON export/import.

---

## 5. Browser Bridge (JXA)

### 5.1 Architecture

A `BrowserBridge` protocol abstracts tab reading and restoring:

```swift
protocol BrowserBridge {
    func readAllTabs() async throws -> [BrowserTab]
    func restoreTabs(_ tabs: [BrowserTab], mode: BrowserRestoreMode) async throws -> Int
}
```

Three implementations:
- **`WebKitBridge`** — Safari, Orion (WebKit JXA dictionary)
- **`ChromiumBridge`** — Chrome, Brave, Edge, Opera, Vivaldi (identical Chromium JXA dictionary)
- **`UnscriptableBridge`** — Arc, Firefox (no scripting dictionary; can open URLs but can't read tabs)

`BrowserBridgeFactory.create(for:)` selects the correct implementation by checking the browser's engine.

### 5.2 Reading Tabs

The JXA script is parameterized by the browser's `jxaAppName`:
```javascript
var app = Application('Safari');         // or 'Google Chrome', 'Brave Browser', etc.
var windows = app.windows();
var tabs = [];
for (var w = 0; w < windows.length; w++) {
    var windowTabs = windows[w].tabs();
    for (var t = 0; t < windowTabs.length; t++) {
        tabs.push({
            url: windowTabs[t].url(),
            title: windowTabs[t].name(),
            windowIndex: w,
            index: t,
            browserId: "com.apple.Safari"
        });
    }
}
JSON.stringify(tabs);
```

### 5.3 Restoring Tabs

Tabs are restored per-browser-group. The `BrowserRestoreMode` enum (`.newWindow`, `.currentWindow`) maps to the appropriate JXA commands. For unscriptable browsers, `NSWorkspace.shared.open(_:withApplicationAt:)` is used instead.

---

## 6. Multi-Browser Capture & Restore

### 6.1 Capture All (`takeSnapshotOfAllBrowsers`)

Uses `TaskGroup` with `Result<[BrowserTab], BrowserCaptureFailure>` for concurrent capture across all running readable browsers. Partial failures are surfaced via `CapturePartialFailure` (carries the persisted `Snapshot` so the UI can display it immediately).

### 6.2 Restore (`restoreSnapshot` / `restoreTabs`)

Tabs are grouped by `browserId` and restored to their original browsers via `restoreGroups()`. Partial failures are surfaced via `RestorePartialFailure` (carries `totalRestored` count and per-browser errors).

### 6.3 Dependency Injection for Testing

`SnapshotService.init` accepts a `bridgeProvider: @Sendable (Browser) -> any BrowserBridge` closure (defaults to `BrowserBridgeFactory.create`). Tests inject a `MockBridge` to control success/failure behavior.

---

## 7. UI Architecture

### 7.1 Main Window Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  Sidebar (Snapshots)             │  Detail (Tabs)                │
│                                  │                               │
│  [Browser Filter: All Snapshots] │  ┌─────────────────────────┐ │
│  ┌────────────────────────────┐  │  │ Snapshot Name (editable)│ │
│  │ 🔍 Search Bar              │  │  │ [Capture All] [Safari]  │ │
│  ├────────────────────────────┤  │  │ [Chrome]                │ │
│  │ Snapshot Card              │  │  ├─────────────────────────┤ │
│  │ 📷 [CaptureAll][Safari][Ch]│  │  │ Tab Row 🌐 example.com │ │
│  │    Jun 28 — 8 tabs          │  │  │           [Safari] pill │ │
│  ├────────────────────────────┤  │  │ Tab Row 🌐 google.com  │ │
│  │ Snapshot Card              │  │  │           [Chrome] pill │ │
│  │ 📷 Jun 28 — 5 tabs         │  │  └─────────────────────────┘ │
│  └────────────────────────────┘  │  [Restore All] [Export][🗑]  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Key UI Components

- **ContentViewModel** — Toolbar camera menu: ⌘N captures frontmost, ⌘⇧N captures all, individual browser buttons
- **SnapshotListViewModel** — `BrowserFilter` enum (`.all`, `.captureAll`, `.specific(Browser)`) with dynamic `availableBrowserFilters`; filter + search composable
- **SnapshotCard** — Colored browser pills with brand tints; "Capture All" badge for multi-browser snapshots
- **SnapshotDetailView** — "Capture All" header badge + browser pills; browser-aware restore
- **TabRow** — Per-tab browser badge with brand color
- **RestoreOptionsSheet** — Mode picker + browser target dropdown (defaults to "Original Browser(s)")
- **SettingsView** — Per-browser permissions grid; dynamic auto-snapshot target picker

---

## 8. Auto-Snapshot System

### 8.1 Dynamic Targets

`AutoSnapshotTarget` is a struct (not enum) with static `.frontmost` and `.allRunning` constants, plus dynamically computed `installedBrowserTargets` from `Browser.installedBrowsers`. Storage uses id strings (`"frontmost"`, `"allRunning"`, `"browser:com.apple.Safari"`) with migration from old enum raw values.

### 8.2 Intervals

Same as 1.0.x: 30 min, 1h, 2h, 4h presets + custom (min 5 min).

---

## 9. Permissions & Security

- **Per-browser Automation permission** — checked via JXA probe for each installed readable browser
- **PermissionsService** stores per-browser permission state in a `[Browser: Bool]` dictionary
- iCloud entitlements detected at runtime via `SecTaskCopyValueForEntitlement`

---

## 10. Soft-Delete Trash System

Unchanged from 1.0.x — soft-delete with 30-day auto-purge.

---

## 11. Sparkle Auto-Updates

Sparkle 2.x checks `appcast.xml` on the `main` branch, compares `sparkle:version` (build number) against the local `CFBundleVersion`, validates the EdDSA `edSignature`, and downloads the DMG from the GitHub release URL.

**Update publishing flow:**
1. Bump version in Info.plist
2. Build and sign the DMG
3. Sign the DMG with `Sparkle/bin/sign_update`
4. Update `appcast.xml` with the new version's metadata + edSignature + file length
5. Commit, push, create GitHub Release with the DMG asset

---

## 12. iCloud Sync

Unchanged from 1.0.x — implemented but disabled in public builds due to AMFI requirements.

---

## 13. Test Coverage

**164 tests across 16 suites:**

| Suite | Tests | Area |
|-------|-------|------|
| BrowserBridgeTests | 18 | BrowserTab model, BrowserBridgeError, JXA |
| SnapshotServiceTests | 27 | CRUD, search, trash, cleanup |
| RestoreServiceTests | 18 | RestorePartialFailure, restoreGroups, MockBridge |
| AutoSnapshotTargetTests | 28 | Dynamic targets, migration, filtering |
| SnapshotDiffTests | 8 | URL diffing |
| SnapshotExportTests | 14 | JSON export/import |
| SyncServiceTests | 19 | iCloud sync state |
| AutoNamerTests | 10 | Naming logic |
| PermissionsServiceProbeTests | 4 | TCC probe |
| SettingsTabTests | 5 | Settings UI |

---

*Last updated: June 28, 2026*
