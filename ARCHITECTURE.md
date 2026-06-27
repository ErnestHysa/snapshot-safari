# 🦁 Snapshot Safari — Architecture Document

> **Version:** 1.0.2
> **Bundle ID:** `com.ernest.snapshot-safari`
> **Distribution:** `.dmg` via ad-hoc signing (public) or Developer ID + notarization (signed)

---

## 1. Product Overview

Snapshot Safari is a native macOS application that captures all open Safari tabs into named
**snapshots**, allowing users to close tabs to free RAM and restore them later — individually
or all at once. It supports selective tab restore, snapshot comparison/diffing, auto-snapshots
on a schedule, JSON export/import, soft-delete with trash recovery, and iCloud sync (requires
Apple Developer Program).

### Core Flow

```
Safari (many tabs open)
      │
      ▼  User clicks "Take Snapshot" (⌘N)
┌─────────────────┐
│ OSAScript / JXA │── Queries Safari → returns [{url, title, windowIndex, index}]
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   SwiftData DB   │── Stores snapshot + tabs (local SQLite)
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│  SwiftUI List View   │── Displays snapshots with favicons
└────────┬────────────┘
         │
    User clicks "Restore"
         │
         ▼
┌─────────────────┐
│ OSAScript / JXA │── Opens tabs in Safari (new or current window)
└─────────────────┘
```

---

## 2. Technology Stack

| Layer            | Technology                          | Rationale                                    |
| ---------------- | ----------------------------------- | -------------------------------------------- |
| Language         | Swift 6                             | Full strict concurrency, modern macOS        |
| UI Framework     | SwiftUI                             | Declarative, dark/light, NavigationSplitView |
| Data Persistence | SwiftData (`.sqlite` backing store) | Apple-native ORM, `#Predicate`, migrations   |
| Safari Bridge    | JXA via `OSAScript`                 | In-process, returns structured JSON          |
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
│   │   ├── Snapshot.swift                        # SwiftData model: snapshot with tabs
│   │   ├── TabEntry.swift                        # SwiftData model: individual tab
│   │   ├── SnapshotDiff.swift                    # Diff computation between snapshots
│   │   └── SnapshotExport.swift                  # Codable export/import format
│   ├── Services/
│   │   ├── SafariBridge.swift                    # JXA → Safari read/restore tabs
│   │   ├── SnapshotService.swift                 # CRUD, search, trash, export/import
│   │   ├── AutoSnapshotManager.swift             # Timer-based auto-snapshot loop
│   │   ├── PermissionsService.swift              # Automation permission check + probe
│   │   ├── SyncService.swift                     # iCloud sync + runtime entitlement check
│   │   ├── FaviconService.swift                  # Cached favicon fetching
│   │   └── SparkleUpdater.swift                  # Auto-update orchestration
│   ├── ViewModels/
│   │   └── SnapshotListViewModel.swift           # Observable state for the main UI
│   ├── Utilities/
│   │   └── AutoNamer.swift                       # Smart snapshot name generation
│   └── Views/
│       ├── ContentView.swift                     # Root: NavigationSplitView + toolbar
│       ├── SnapshotListView.swift                # Sidebar list with search
│       ├── SnapshotCard.swift                    # List item with favicon preview
│       ├── SnapshotDetailView.swift              # Tab list + restore/export/delete
│       ├── TabRow.swift                          # Individual tab row with favicon
│       ├── RestoreOptionsSheet.swift             # New/current window picker
│       ├── CompareSnapshotsView.swift            # Visual diff display (added/removed/common)
│       ├── TrashView.swift                       # Recently deleted snapshots
│       ├── SettingsView.swift                    # Multi-tab settings panel
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
    ├── AutoNamerTests.swift                      # 10 naming tests
    ├── SafariBridgeTests.swift                   # 18 JXA + model tests
    ├── SnapshotServiceTests.swift                # 27 CRUD, search, trash, cleanup tests
    ├── SnapshotDiffTests.swift                   # 8 diff algorithm tests
    ├── SnapshotExportTests.swift                 # 14 export/import tests
    ├── SyncServiceTests.swift                    # 19 sync state + entitlement tests
    ├── PermissionsServiceProbeTests.swift        # 4 TCC permission probe tests
    ├── SettingsTabTests.swift                    # 5 settings UI tests
    ├── RestoreModeTests.swift                    # 2 restore mode enum tests
    └── SafariBridgeErrorTests.swift              # 5 error description tests
```

---

## 4. Data Model

### 4.1 Snapshot

```swift
@Model
final class Snapshot {
    var id: UUID
    var name: String                    // Auto-named, user-renamable
    var createdAt: Date
    var updatedAt: Date                 // Updated on rename
    var tabCount: Int                   // Denormalized for fast list display
    var isTrashed: Bool                 // Soft-delete flag
    var deletedAt: Date?                // Timestamp for 30-day auto-purge
    var isAutoSnapshot: Bool            // Distinguishes manual vs auto
    @Relationship(deleteRule: .cascade) var tabs: [TabEntry]
}
```

### 4.2 TabEntry

```swift
@Model
final class TabEntry {
    var id: UUID
    var url: String                     // Full URL (or "about:blank" if nil)
    var domain: String                  // Extracted domain (for grouping)
    var title: String                   // Page title from Safari
    var windowIndex: Int                // Which window the tab was in
    var index: Int                      // Order within window
    var snapshot: Snapshot?             // Inverse relationship
}
```

### 4.3 SnapshotDiff

A pure value type (not persisted) that compares two snapshots:

```swift
struct SnapshotDiff {
    let added: [TabEntry]       // In newer but not older (case-insensitive URL match)
    let removed: [TabEntry]     // In older but not newer
    let common: [TabEntry]      // In both
    let older: Snapshot
    let newer: Snapshot
}
```

### 4.4 SnapshotExport

A `Codable` envelope for JSON export/import:

```swift
struct SnapshotExport: Codable {
    let version: Int
    let exportedAt: Date
    let snapshots: [SnapshotData]
}
```

---

## 5. Safari Bridge (JXA)

### 5.1 Strategy

Use **JXA (JavaScript for Automation)** via `OSAScript` executed in-process. This:
- Returns structured JSON (arrays/objects) unlike AppleScript's text returns
- Registers the TCC Automation permission under the app's bundle ID (not `com.apple.osascript`)
- Supports both read (query tabs) and write (open new tabs/windows) operations

### 5.2 Reading Tabs

```javascript
var safari = Application('Safari');
var windows = safari.windows();
var tabs = [];
for (var w = 0; w < windows.length; w++) {
    var windowTabs = windows[w].tabs();
    for (var t = 0; t < windowTabs.length; t++) {
        tabs.push({
            url: windowTabs[t].url(),
            title: windowTabs[t].name(),
            windowIndex: w,
            index: t
        });
    }
}
JSON.stringify(tabs);
```

Executed via a hybrid GCD approach: background queue first (fast, non-blocking), with automatic
retry on the main thread if TCC rejects the background-thread AppleEvent. A `withTimeout`
mechanism guards against hung scripts.

### 5.3 Restoring Tabs

Two modes, both using JXA:

**New Window:**
```javascript
var safari = Application('Safari');
var doc = safari.Document({url: tabs[0].url});
safari.documents.push(doc);
// ... additional tabs pushed to the new document
```

**Current Window (append):**
```javascript
var safari = Application('Safari');
// Append tabs to the frontmost window, or openLocation if none open
```

The restore function returns the count of successfully restored tabs, which is used
to show a "Successfully restored N tabs" alert. After restore, Safari is brought to
the foreground via `NSRunningApplication.activate(.activateIgnoringOtherApps)`.

---

## 6. UI Architecture

### 6.1 Main Window Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Sidebar (Snapshots)          │  Detail (Tabs)               │
│                               │                               │
│  ┌───────────────────────┐    │  ┌─────────────────────────┐ │
│  │ Search Bar             │    │  │ Snapshot Name (editable)│ │
│  ├───────────────────────┤    │  ├─────────────────────────┤ │
│  │ Snapshot Card          │    │  │ Tab Row  🌐 example.com │ │
│  │ 📷 Mar 24 — 15 tabs    │    │  │ Tab Row  🌐 google.com  │ │
│  ├───────────────────────┤    │  │ Tab Row  🌐 github.com  │ │
│  │ Snapshot Card          │    │  │                         │ │
│  │ 📷 Mar 23 — 8 tabs     │    │  │ [Restore All]           │ │
│  └───────────────────────┘    │  │ [Export] [Delete]        │ │
│                               │  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 Navigation

- **NavigationSplitView** (sidebar + detail on macOS)
- Sidebar: List of snapshots sorted by date (newest first), with search
- Detail: Selected snapshot's tabs with individual checkboxes for selective restore
- Toolbar: Take Snapshot, Import, Export, Settings, Trash button
- `.overlay` for "Working with Safari…" progress indicator on the outer `Group`

### 6.3 RestoreOptionsSheet

When user clicks "Restore", a sheet appears:
- **New Safari Window** — opens tabs in a fresh window
- **Current Window** — appends to the frontmost window
- Selected tabs or all tabs, depending on user selection

### 6.4 Settings

Multi-tab settings panel with native NSWindow chrome:
- **General**: Theme (Light/Dark/System)
- **Auto-Snapshots**: Enable toggle, interval picker (presets + custom)
- **Appearance**: Theme override
- **Storage**: Data management
- **Sync**: iCloud sync toggle (disabled if no entitlement)
- **About**: Version info, "Check for Updates" button, GitHub link

### 6.5 CompareSnapshotsView

Visual diff between two snapshots:
- 🟢 **Added** tabs (in newer, not in older)
- 🔴 **Removed** tabs (in older, not in newer)
- ⚪ **Common** tabs (unchanged)
- Case-insensitive URL matching

---

## 7. Auto-Snapshot System

### 7.1 Architecture

```
AutoSnapshotManager (@MainActor)
├── Timer (runs while app is active)
│   └── Fires at configured interval
├── UserDefaults saves toggle + interval
│
└── On fire:
    1. Check if Safari is running
    2. If yes, take snapshot (via SafariBridge)
    3. Name: "Auto — Mar 24, 2026"
    4. Save to SwiftData (isAutoSnapshot: true)
    5. Fail silently if Safari isn't running
```

### 7.2 Intervals

| Preset  | Seconds   |
| ------- | --------- |
| 30 min  | 1800      |
| 1 hour  | 3600      |
| 2 hours | 7200      |
| 4 hours | 14400     |
| Custom  | User-set (min 5 min) |

- Auto-snapshots are tagged with `isAutoSnapshot: true` for filtering
- The auto-snapshot state and interval persist across app restarts
- Timer-based; the app must be running (background is fine)

---

## 8. Permissions & Security

### 8.1 Required Permissions

| Permission            | Why Needed                           | How to Request                        |
| --------------------- | ------------------------------------ | ------------------------------------- |
| Automation → Safari   | Query tabs + open tabs via JXA       | Automatic on first script execution   |

### 8.2 Permission Flow

1. User opens app → Welcome screen explains the need for Safari access
2. Clicking "Grant Permission" triggers a JXA execution → macOS shows TCC dialog
3. If denied: Show branded sheet with step-by-step instructions to System Settings
4. Permission probe detects whether the app appears in Automation settings
5. In-process `OSAScript` execution ensures the permission is registered under `com.ernest.snapshot-safari`

### 8.3 Privacy

- All data stays **local** (SQLite via SwiftData)
- No analytics, no tracking, no telemetry
- Favicon fetches use Google's public service (`google.com/s2/favicons`)
- URLs are never sent to any server (except favicon fetches)
- iCloud sync is opt-in and requires Apple Developer Program

---

## 9. Search Implementation

Search across snapshots by name, and across tabs by URL, title, and domain.

Uses `#Predicate` with SwiftData for efficient filtering at the database level:

```swift
#Predicate<Snapshot> {
    $0.name.localizedStandardContains(searchText)
    || $0.tabs.contains {
        $0.url.localizedStandardContains(searchText)
        || $0.title.localizedStandardContains(searchText)
        || $0.domain.localizedStandardContains(searchText)
    }
}
```

---

## 10. Soft-Delete Trash System

- Snapshots are soft-deleted with `isTrashed = true` and `deletedAt = Date()`
- TrashView shows recently deleted snapshots with count badge in toolbar
- Restore from trash reverses the flags
- Auto-purge: snapshots in trash for > 30 days are permanently deleted
- Cleanup runs on app launch via `cleanUpOldTrash()`

---

## 11. Sparkle Auto-Updates

Sparkle 2.x is fully integrated:

- `SPUStandardUpdaterController` in `SparkleUpdater.swift`
- `SUFeedURL` in Info.plist points to `appcast.xml` on the `main` branch
- `SUPublicEDKey` validates update signatures
- `SparkleUpdateChecker` (`@Observable`) provides SwiftUI-friendly state
- "Check for Updates" menu item calls `SparkleUpdater.shared.checkForUpdates()`
- Disabled on first launch (`SUEnableAutomaticChecks = false`) to avoid the Sparkle first-run prompt

**Update publishing flow:**
1. Bump version in Info.plist
2. Build and sign the DMG
3. Sign the DMG with `Sparkle/bin/sign_update` (private key in Keychain)
4. Update `appcast.xml` with the new version's metadata + edSignature + length
5. Commit and push; create a GitHub Release with the DMG asset
6. Sparkle picks up the update on next check

---

## 12. iCloud Sync

iCloud Sync is fully implemented but **disabled in the public build** because the CloudKit
container + iCloud services entitlements require a Developer ID signature (AMFI kills
ad-hoc binaries that request them).

- `SyncService` detects runtime entitlements via `SecTaskCopyValueForEntitlement`
- When CloudKit entitlements are absent, the toggle is disabled with an explanation
- When present (signed build), SwiftData's `ModelConfiguration.cloudKitDatabase` handles sync
- Sync state is observed and displayed in Settings → Sync tab

---

## 13. Test Coverage

**114 tests across 13 suites:**

| Suite | Tests | Area |
|-------|-------|------|
| AutoNamerTests | 10 | Snapshot naming logic |
| SafariBridgeTests | 18 | Tab model, Codable, error messages |
| SnapshotServiceTests | 27 | CRUD, search, trash, cleanup |
| SnapshotDiffTests | 8 | URL diffing algorithm |
| SnapshotExportTests | 14 | JSON export/import roundtrip |
| SyncServiceTests | 19 | iCloud sync state, entitlements |
| PermissionsServiceProbeTests | 4 | TCC permission probe |
| SettingsTabTests | 5 | Settings UI |
| RestoreModeTests | 2 | Restore mode enum |
| SafariBridgeErrorTests | 5 | Error descriptions |

Tests use Swift Testing (`@Test`, `#expect`) with in-memory `ModelConfiguration` for
SwiftData tests. Pure logic tests run in plain structs; SwiftData tests use `@MainActor`.

---

## 14. Key Architectural Decisions

| Decision                    | Choice                           | Rationale                                                |
| --------------------------- | -------------------------------- | -------------------------------------------------------- |
| Persistence                 | SwiftData                        | Less boilerplate than Core Data, modern Swift syntax     |
| Safari integration          | JXA via OSAScript                | In-process, proper TCC registration, structured JSON     |
| Restore mode                | User chooses per restore         | Maximum flexibility                                      |
| Favicon source              | Google favicons API              | Free, no API key, works for all URLs                     |
| Update framework            | Sparkle 2.x                      | Industry standard, signed updates                        |
| iCloud sync                 | CloudKit via SwiftData           | Apple-native, zero-config when entitled                  |
| Script execution            | Hybrid GCD + main thread retry   | Responsive UI + TCC compatibility for write operations   |
| Concurrency                 | `@MainActor` + Swift 6 strict    | Safe access to SwiftData and AppKit from main thread     |
| State management            | `@Observable`                    | Modern SwiftUI, no `ObservableObject` boilerplate        |

---

*Last updated: June 27, 2026*
