# 🦁 Snapshot Safari — Architecture Document

> **Version:** 1.0 (MVP)
> **Bundle ID:** `com.ernest.snapshot-safari`
> **Distribution:** `.dmg` via Developer ID signing + Apple notarization

---

## 1. Product Overview

Snapshot Safari is a native macOS application that captures all open Safari tabs into named **snapshots**, allowing users to close tabs to free RAM and restore them later — individually or all at once.

### Core Flow

```
Safari (many tabs open)
      │
      ▼  User clicks "Take Snapshot"
┌─────────────────┐
│ AppleScript/JXA │── Queries Safari → returns [{url, title, windowIndex}]
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   SwiftData DB   │── Stores snapshot + tabs
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
│ AppleScript/JXA │── Opens tabs in Safari (new or current window)
└─────────────────┘
```

---

## 2. Technology Stack

| Layer            | Technology                          | Rationale                                    |
| ---------------- | ----------------------------------- | -------------------------------------------- |
| Language         | Swift 5.9+                          | Native macOS, best AppleScript bridging      |
| UI Framework     | SwiftUI                             | Declarative, modern, dark/light mode built-in |
| Data Persistence | SwiftData (`.sqlite` backing store) | Apple-native ORM, minimal boilerplate         |
| Safari Bridge    | AppleScript via `NSAppleScript`     | No extension needed, works with SIP enabled  |
| Background Timer | `Timer` + `BackgroundTask`          | Lightweight, no server needed                |
| Favicons         | Safari Tab URL favicon fetch        | `https://www.google.com/s2/favicons?domain=` |
| Build System     | Xcode 15+ / Swift Package Manager   | Standard Apple toolchain                     |
| Distribution     | Developer ID + Notarization         | Outside Mac App Store `.dmg`                 |

---

## 3. Project Structure

```
Snapshot-Safari/
├── ARCHITECTURE.md              # This file
├── SnapshotSafari/
│   ├── SnapshotSafariApp.swift   # App entry point, SwiftUI App lifecycle
│   ├── Models/
│   │   ├── Snapshot.swift        # SwiftData @Model — a single snapshot
│   │   └── TabEntry.swift        # SwiftData @Model — a single tab within a snapshot
│   ├── Services/
│   │   ├── SafariBridge.swift    # JXA/AppleScript execution layer
│   │   ├── SnapshotService.swift # CRUD operations on snapshots/tabs
│   │   ├── AutoSnapshotManager.swift  # Timer-based auto-snapshot engine
│   │   ├── FaviconService.swift  # Fetch favicons for URLs
│   │   └── PermissionsService.swift   # Accessibility/Automation permission prompts
│   ├── ViewModels/
│   │   ├── SnapshotListViewModel.swift
│   │   ├── SnapshotDetailViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Views/
│   │   ├── ContentView.swift          # Root split-view layout
│   │   ├── SnapshotListView.swift     # Main list of snapshots
│   │   ├── SnapshotCard.swift         # Individual card (name, date, count, favicons)
│   │   ├── SnapshotDetailView.swift   # Full detail with tab list
│   │   ├── TabRow.swift              # Single tab row with favicon
│   │   ├── RestoreOptionsSheet.swift # "New Window" vs "Current Window" picker
│   │   ├── SettingsView.swift        # Preferences window
│   │   └── SearchBar.swift           # Reusable search component
│   ├── Utilities/
│   │   ├── DateFormatter+Ext.swift   # "Mar 24, 2026" style formatting
│   │   ├── String+Ext.swift          # URL validation, domain extraction
│   │   └── AutoNamer.swift           # Generates snapshot names
│   └── Resources/
│       ├── Assets.xcassets           # App icon, accent colors
│       └── Info.plist                # Bundle config, permissions descriptions
├── SnapshotSafari.xcodeproj/     # Xcode project
├── Package.swift                 # (if using SPM)
└── Scripts/
    └── sign-notarize.sh          # CI script for .dmg building + notarization
```

---

## 4. Data Model

### 4.1 Snapshot

```swift
@Model
final class Snapshot {
    #Unique<Snapshot>([\.id])

    var id: UUID
    var name: String                    // Auto-named, user-renamable
    var createdAt: Date
    var updatedAt: Date                 // Updated on rename
    var tabCount: Int                   // Denormalized for fast list display
    var tags: [String]                  // Future: user-defined tags
    @Relationship(deleteRule: .cascade) var tabs: [TabEntry]

    init(name: String, tabs: [TabEntry]) { ... }
}
```

### 4.2 TabEntry

```swift
@Model
final class TabEntry {
    #Unique<TabEntry>([\.id])

    var id: UUID
    var url: String                     // Full URL
    var domain: String                  // Extracted domain (for search grouping)
    var title: String                   // Page title from Safari
    var windowIndex: Int                // Which window the tab was in
    var index: Int                      // Order within window
    var snapshot: Snapshot?             // Inverse relationship

    init(url: String, title: String, windowIndex: Int, index: Int) { ... }
}
```

### 4.3 Indexes & Search

SwiftData automatically indexes `#Unique` properties. For full-text search across titles, URLs, and domains:

- Query: `#Predicate<Snapshot> { $0.name.contains(searchText) || $0.tabs.contains { $0.url.contains(searchText) || $0.title.contains(searchText) || $0.domain.contains(searchText) } }`
- Performance: With typical usage (hundreds of snapshots, thousands of tabs), predicate filtering on string containment is fast enough for MVP. If needed, add a materialized search index in a future phase.

---

## 5. Safari Bridge (AppleScript/JXA)

### 5.1 Strategy

Use **JXA (JavaScript for Automation)** via `NSAppleScript` because it returns structured data (arrays/objects) that can be parsed as JSON, unlike AppleScript's text-based returns.

### 5.2 Reading Tabs

```javascript
// JXA script: get all tabs from all windows
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

Executed from Swift:

```swift
func executeJXA(_ script: String) throws -> String {
    let appleScript = NSAppleScript(source: script)
    var error: NSDictionary?
    let result = appleScript?.executeAndReturnError(&error)
    if let error = error {
        throw SafariBridgeError.scriptError(error)
    }
    return result?.stringValue ?? ""
}
```

### 5.3 Restoring Tabs

```javascript
// JXA script: open tabs in Safari
var safari = Application('Safari');
var json = '{JSON_ARRAY_OF_TABS}'; // injected by Swift
var tabs = JSON.parse(json);

// Open in new window
var newWindow = safari.Window().make();
for (var i = 0; i < tabs.length; i++) {
    var tab = newWindow.tabs.push(safari.Tab({url: tabs[i].url}));
}
```

Alternative: Open in **current frontmost window** by appending to existing tabs.

### 5.4 Permission Handling

- macOS will prompt for Automation permission on first invocation.
- Use `PermissionsService` to check/request access via `AXIsProcessTrusted()` and AppleScript permission dialogs.
- If permission denied, show a branded sheet with step-by-step instructions:
  1. Open System Settings → Privacy & Security → Automation
  2. Enable "Snapshot Safari" for Safari

---

## 6. UI Architecture

### 6.1 Main Window Layout

```
┌─────────────────────────────────────────────────────┐
│  Sidebar (Snapshots)      │  Detail (Tabs)          │
│                           │                         │
│  ┌─────────────────────┐  │  ┌───────────────────┐  │
│  │ Search Bar          │  │  │ Snapshot Name     │  │
│  ├─────────────────────┤  │  │ (Editable)        │  │
│  │ Snapshot Card       │  │  ├───────────────────┤  │
│  │ 📷 Mar 24 — 15 tabs │  │  │ Tab Row           │  │
│  │  🕐 2 hours ago     │  │  │ 🌐 example.com    │  │
│  ├─────────────────────┤  │  │ Tab Row           │  │
│  │ Snapshot Card       │  │  │ 🌐 google.com     │  │
│  │ 📷 Mar 23 — 8 tabs  │  │  │ Tab Row           │  │
│  │  🕐 Yesterday       │  │  │ 🌐 github.com     │  │
│  ├─────────────────────┤  │  │                   │  │
│  │ "+" New Snapshot    │  │  │ [Restore All]     │  │
│  └─────────────────────┘  │  └───────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### 6.2 Navigation

- **NavigationSplitView** (three-column on large, two-column on compact)
- Sidebar: List of snapshots sorted by date (newest first)
- Detail: Selected snapshot's tabs
- Toolbar: "Take Snapshot" button, search field, settings gear

### 6.3 RestoreOptionsSheet

When user clicks "Restore", show a sheet:

```
┌──────────────────────────────┐
│  Restore Snapshot            │
│                              │
│  How would you like to open  │
│  these 15 tabs?              │
│                              │
│  ○ New Safari Window         │
│  ● Current Window (append)   │
│                              │
│  [Cancel]  [Restore]         │
└──────────────────────────────┘
```

### 6.4 Appearance

- Follows system appearance by default.
- Settings tab allows override: Dark / Light / System.
- Uses `.preferredColorScheme()` environment modifier.
- Favicon cards use `AsyncImage` with favicon URLs.
- Snapshot cards show first 4-6 favicons in a horizontal row as visual preview.

---

## 7. Auto-Snapshot System

### 7.1 Architecture

```
AutoSnapshotManager
├── Timer (runs while app is active)
│   └── Fires at configured interval
├── UserDefaults saves selected interval
│
└── On fire:
    1. Check if Safari is running
    2. If yes, take snapshot (via SafariBridge)
    3. Name: "Auto — Mar 24, 2026 — 15 tabs"
    4. Save to SwiftData
    5. Post notification (optional, user-configurable)
```

### 7.2 Intervals

| Preset  | Seconds   |
| ------- | --------- |
| 30 min  | 1800      |
| 1 hour  | 3600      |
| 2 hours | 7200      |
| 4 hours | 14400     |
| Custom  | User-set  |

- Auto-snapshots are tagged internally (e.g., `isAutoSnapshot: Bool` or naming prefix "Auto —") so user can filter them.
- Auto-snapshots do not replace manual ones — both coexist.

### 7.3 Background Operation

- MVP: App must be running (in background is fine).
- If user closes the app, auto-snapshots pause.
- Run-in-background via `.background` scene phase handling.

---

## 8. Search Implementation

### 8.1 Search Scope

Search across:
- Snapshot names
- Tab titles
- Tab URLs
- Domains

### 8.2 UI

- Search field in sidebar (`.searchable()` modifier)
- Results filter the sidebar snapshot list in real-time
- Matching tabs are highlighted in the detail view
- Search shows snapshots that contain at least one matching tab, with a match count badge

### 8.3 Query

```swift
@MainActor
class SnapshotListViewModel: ObservableObject {
    @Published var searchText = ""

    var filteredSnapshots: [Snapshot] {
        guard !searchText.isEmpty else { return allSnapshots }
        return allSnapshots.filter { snapshot in
            snapshot.name.localizedCaseInsensitiveContains(searchText)
            || snapshot.tabs.contains { tab in
                tab.title.localizedCaseInsensitiveContains(searchText)
                || tab.url.localizedCaseInsensitiveContains(searchText)
                || tab.domain.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}
```

---

## 9. Permissions & Security

### 9.1 Required Permissions

| Permission            | Why Needed                           | How to Request                        |
| --------------------- | ------------------------------------ | ------------------------------------- |
| Automation → Safari   | Query tabs + open tabs via AppleScript | Automatic on first script execution   |
| Accessibility (maybe) | Only if AppleScript fails            | `AXIsProcessTrusted()` check          |

### 9.2 Permission Flow on First Launch

1. User opens app → Sees **Welcome Screen**
2. Welcome screen explains: "I need permission to control Safari"
3. User clicks "Grant Permission" → Triggers AppleScript execution → macOS shows permission dialog
4. If denied: Show instructions with deep link to System Settings
5. On success: Proceed to main interface

### 9.3 Privacy Notes

- All data stays **local** (no network calls except favicon fetches)
- No analytics, no tracking, no telemetry
- Favicon fetches go to Google's public favicon service (`https://www.google.com/s2/favicons?domain=`)
- URLs are never sent anywhere

---

## 10. Settings

### 10.1 Settings Window

| Section           | Controls                                                            |
| ----------------- | ------------------------------------------------------------------- |
| General           | Launch at login (toggle), Default restore behavior (picker)         |
| Auto-Snapshots    | Enable toggle, Interval picker (presets + custom)                   |
| Appearance        | Theme picker (Dark / Light / System)                                |
| About             | Version, License, GitHub link, "Check for Updates" button (future)  |

### 10.2 Launch at Login

Use `SMAppService.mainApp` (macOS 13+) or `SMLoginItemSetEnabled` for backward compatibility.

```swift
import ServiceManagement

func setLaunchAtLogin(_ enabled: Bool) {
    try? SMAppService.mainApp.register() // or unregister()
}
```

---

## 11. Phases & Roadmap

### Phase 1 — MVP (Current)

- [x] Project setup (Xcode, SwiftData models)
- [ ] SafariBridge: Read all tabs via JXA
- [ ] SafariBridge: Restore all tabs (new window only)
- [ ] Snapshot CRUD (take, list, delete)
- [ ] Auto-naming + manual rename
- [ ] Snapshot list view with favicon cards
- [ ] Snapshot detail view with tab rows
- [ ] Restore with options sheet (new vs current window)
- [ ] Permissions setup flow
- [ ] Search across snapshots and tabs
- [ ] Manual snapshot button in toolbar
- [ ] Auto-snapshots (preset intervals)
- [ ] Settings window (theme, auto-snapshot config)
- [ ] App icon

### Phase 2 — Polish

- [ ] Individual tab restore (pick specific tabs, not just all)
- [ ] Snapshot comparison / diffing
- [ ] Undo delete
- [ ] Snapshot export (JSON/CSV of URLs)
- [ ] Keyboard shortcuts
- [ ] Sparkle auto-updates
- [ ] Custom interval in auto-snapshots

### Phase 3 — Advanced

- [ ] iCloud sync
- [ ] Safari Tab Group tracking
- [ ] Multi-profile Safari support
- [ ] Safari Web Extension for richer data (favicons natively, scroll position)
- [ ] Snapshot scheduling (specific times of day)
- [ ] Tagging and filtering
- [ ] Smart search (fuzzy matching, recent-first)

---

## 12. Distribution & Build

### 12.1 Code Signing

```bash
# Developer ID certificate required
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Your Name (TEAMID)" \
    SnapshotSafari.app
```

### 12.2 Notarization

```bash
# Zip the app
ditto -c -k --keepParent SnapshotSafari.app SnapshotSafari.zip

# Upload to Apple
xcrun notarytool submit SnapshotSafari.zip \
    --apple-id "your@email.com" \
    --team-id "TEAMID" \
    --password "@keychain:AC_PASSWORD" \
    --wait

# Staple the ticket
xcrun stapler staple SnapshotSafari.app
```

### 12.3 DMG Creation

```bash
# Create a read/write DMG, then convert to compressed
hdiutil create -srcfolder SnapshotSafari.app \
    -volname "Snapshot Safari" \
    -fs HFS+ \
    -format UDZO \
    SnapshotSafari.dmg
```

---

## 13. Dependencies

### External (none for MVP)

No third-party dependencies for MVP. Everything uses Apple frameworks:
- `SwiftData` — persistence
- `SwiftUI` — UI
- `AppKit` — NSApplication, menu extras
- `ServiceManagement` — launch at login
- `Foundation` — URLSession, JSON, dates

### Future Dependencies

| Dependency | Purpose                     | Phase |
| ---------- | --------------------------- | ----- |
| Sparkle    | Auto-updates                | 2     |
| CloudKit   | iCloud sync                 | 3     |

---

## 14. Development Workflow

### 14.1 Starting Development

```bash
# 1. Create the Xcode project
xcodebuild -create-xcproject ...

# 2. Open in Xcode
open SnapshotSafari.xcodeproj

# 3. Enable App Sandbox (required for notarization)
#    - Entitlements: com.apple.security.automation.apple-events
```

### 14.2 Testing

- Unit tests for: `AutoNamer`, `SafariBridge` (mock), `AutoSnapshotManager`, Search logic
- UI tests via XCUITest for: snapshot creation flow, restore flow, settings

### 14.3 Git Workflow

```bash
main        # Release-ready code
├── develop # Integration branch
├── feat/*  # Feature branches
└── fix/*   # Bug fix branches
```

---

## 15. Key Architectural Decisions

| Decision                    | Choice                           | Rationale                                                |
| --------------------------- | -------------------------------- | -------------------------------------------------------- |
| SwiftData vs Core Data      | SwiftData                        | Less boilerplate, modern Swift syntax                    |
| AppleScript vs Extension    | AppleScript/JXA                  | Simpler setup, no extension deployment                   |
| New Window vs Append        | User chooses per restore         | Maximum flexibility                                      |
| Favicon source              | Google favicons API              | Free, no API key needed, works for all URLs              |
| Search approach             | In-memory predicate filtering    | Fast enough for MVP scale, no index maintenance overhead |
| Auto-snapshot persistence   | Timer while app is alive         | Simple, no background daemon needed for MVP              |

---

*Last updated: June 24, 2026*
