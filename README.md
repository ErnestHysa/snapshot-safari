# Snapshot Safari

> Save and restore your Safari tabs — free up RAM without losing anything.

Snapshot Safari is a native macOS app that captures all your open Safari tabs into named snapshots, lets you restore them later in new or current windows, compare changes between snapshots, and automate the process on a schedule.

Built with **SwiftUI**, **SwiftData**, and **Sparkle**.

## Features

### 📸 Snapshot Management

- **Take snapshots** of all open Safari tabs with one click (⌘N)
- **Auto-naming** — snapshots are automatically named with date, tab count, and type (manual vs. auto)
- **Search** — find snapshots by name, URL, tab title, or domain
- **Rename** — give snapshots meaningful names
- **Delete with undo** — snapshots go to trash and are auto-cleaned after 30 days
- **Export/Import** — share snapshots as JSON files (⌘E export, ⌘I import)

### 🔄 Tab Restore

- **Restore all tabs** or select specific tabs to restore
- **Choose restore mode** — open in a new Safari window or append to the current window
- **Tab preview** — see favicons, URLs, and domains for every tab in a snapshot

### 📊 Comparison & Diffing

- **Compare two snapshots** to see what tabs were added, removed, or unchanged
- **Case-insensitive URL matching** — detects the same site regardless of URL casing
- **Visual diff** — color-coded lists with badge counts

### ⏰ Auto-Snapshots

- **Scheduled snapshots** — automatically capture tabs every 30 min, 1h, 2h, or 4h
- **Custom intervals** — set any interval (minimum 5 minutes)
- **Persistent settings** — auto-snapshot state and interval survive app restarts
- **Silent failures** — auto-snapshots fail gracefully when Safari isn't running

### ☁️ iCloud Sync

- **Sync across Macs** — share snapshots via iCloud (requires Apple Developer Program)
- **Persistent preference** — sync toggle survives app restarts
- **Graceful fallback** — if CloudKit isn't available, the app uses local storage

### 🎨 Appearance

- **Light, Dark, and System themes** — follow your macOS preference or choose manually

### 🔄 Auto-Updates

- **Sparkle-powered updates** — automatic update checks and downloads
- **Check for Updates** menu item in the app menu

## Requirements

- macOS 15.0 (Sequoia) or later
- Safari (for reading and restoring tabs)
- Automation permission for Safari (prompted on first launch)

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/ernest/snapshot-safari.git
cd snapshot-safari

# Build and run
swift run

# Or open in Xcode
open Package.swift
```

### Building for Distribution

```bash
# Build the release version
swift build -c release

# The binary will be at:
# .build/release/SnapshotSafari
```

## Setup

### First Launch

1. Open the app — a welcome screen explains what Snapshot Safari does
2. Grant **Automation access** to Safari when prompted (System Settings → Privacy & Security → Automation)
3. Take your first snapshot with ⌘N or the camera button in the toolbar

### Sparkle Auto-Updates (for distribution)

To enable Sparkle updates for your distributed build:

1. Generate an Ed25519 key pair using Sparkle's `generate_keys` tool
2. Replace `SUPublicEDKey` in `Sources/SnapshotSafari/Info.plist` with your public key
3. Publish an `appcast.xml` and update the `SUFeedURL` in Info.plist
4. Sign and notarize your `.app` bundle

### iCloud Sync

To enable iCloud sync across Macs:

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/)
2. Create a CloudKit container with identifier `iCloud.com.ernest.snapshot-safari` on the [Developer Portal](https://developer.apple.com/account/resources/identifiers/container)
3. Sign your app with a provisioning profile that includes the iCloud capability
4. In the app, go to Settings → Sync and enable iCloud Sync (requires restart)

## Usage

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | Take a new snapshot |
| ⌘I | Import snapshots from a JSON file |
| ⌘E | Export the selected snapshot |
| ⇧⌘E | Export all snapshots |
| ⌘, | Open settings |
| ⌘⌫ | Delete the selected snapshot |
| ⌘F | Focus search field (sidebar) |
| Escape | Close sheets / dialogs |

### Taking a Snapshot

1. Make sure Safari is running with some open tabs
2. Press ⌘N or click the camera icon in the toolbar
3. The snapshot appears in the sidebar with an auto-generated name

### Restoring Tabs

1. Select a snapshot in the sidebar
2. In the detail view, click **Restore All** or select specific tabs and click **Restore Selected**
3. Choose whether to open tabs in a **New Safari Window** or the **Current Window**

### Comparing Snapshots

1. Right-click a snapshot in the sidebar
2. Choose **Compare With…** and select another snapshot
3. The comparison view shows:
   - 🟢 **Added** tabs (in the newer snapshot)
   - 🔴 **Removed** tabs (in the older snapshot)
   - ⚪ **Common** tabs (unchanged between both)

### Exporting Snapshots

1. Select a snapshot and press ⌘E (or right-click → Export…)
2. Choose a location to save the `.json` file
3. Share the file with anyone running Snapshot Safari

### Importing Snapshots

1. Press ⌘I or click the import button in the toolbar
2. Select a `.json` export file
3. The snapshots are imported and appear in the sidebar

## Architecture

### Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (`NavigationSplitView`, `@Observable`, `SwiftData`) |
| Persistence | SwiftData (`ModelContainer`, `@Model`, `#Predicate`) |
| Safari Integration | JXA via `osascript` (JavaScript for Automation) |
| Auto-Updates | Sparkle 2.x |
| iCloud Sync | CloudKit (via SwiftData) |
| Minimum OS | macOS 15.0 Sequoia |

### Project Structure

```
SnapshotSafari/
├── Package.swift                          # SPM manifest
├── SnapshotSafari.entitlements            # Sandbox + iCloud entitlements
├── Sources/SnapshotSafari/
│   ├── SnapshotSafariApp.swift            # App entry point, commands, CloudKit init
│   ├── Info.plist                         # Bundle metadata, Sparkle keys
│   ├── Models/
│   │   ├── Snapshot.swift                 # SwiftData model: snapshot with tabs
│   │   ├── TabEntry.swift                 # SwiftData model: individual tab
│   │   ├── SnapshotDiff.swift             # Diff computation between snapshots
│   │   └── SnapshotExport.swift           # Codable export/import format
│   ├── Services/
│   │   ├── SafariBridge.swift             # JXA → Safari read/restore tabs
│   │   ├── SnapshotService.swift          # CRUD, search, trash, export/import
│   │   ├── AutoSnapshotManager.swift      # Timer-based auto-snapshot loop
│   │   ├── PermissionsService.swift       # Automation permission check
│   │   ├── SyncService.swift              # iCloud sync state management
│   │   ├── FaviconService.swift           # Cached favicon fetching
│   │   └── SparkleUpdater.swift           # Auto-update orchestration
│   ├── ViewModels/
│   │   └── SnapshotListViewModel.swift    # Observable state for the main UI
│   ├── Utilities/
│   │   └── AutoNamer.swift                # Smart snapshot name generation
│   └── Views/
│       ├── ContentView.swift              # Root view: split navigation + toolbar
│       ├── SnapshotListView.swift         # Sidebar list with search
│       ├── SnapshotCard.swift             # List item with favicon preview
│       ├── SnapshotDetailView.swift       # Tab list + restore/export/delete
│       ├── TabRow.swift                   # Individual tab row with favicon
│       ├── RestoreOptionsSheet.swift      # New/current window picker
│       ├── CompareSnapshotsView.swift     # Visual diff display
│       ├── TrashView.swift                # Recently deleted snapshots
│       ├── SettingsView.swift             # 7-tab settings panel
│       └── WelcomeView.swift              # First-launch onboarding
└── Tests/SnapshotSafariTests/
    ├── AutoNamerTests.swift               # 10 naming tests
    ├── SafariBridgeTests.swift            # 18 JXA + model tests
    ├── SnapshotServiceTests.swift         # 27 CRUD, search, trash, cleanup tests
    ├── SnapshotDiffTests.swift            # 8 diff algorithm tests
    ├── SnapshotExportTests.swift          # 14 export/import tests
    └── SyncServiceTests.swift             # 15 sync state tests
```

### Key Design Decisions

**SwiftData for persistence** — The app uses SwiftData's `@Model` macros with an in-memory fallback container if local persistence fails. CloudKit sync is conditionally enabled via `ModelConfiguration.cloudKitDatabase`.

**JXA via osascript** — Safari tabs are read and restored using JavaScript for Automation (JXA) scripts executed through `osascript`. This approach is more reliable than AppleScript for parsing structured data (JSON output).

**Soft-delete trash** — Snapshots are soft-deleted with an `isTrashed` flag and `deletedAt` timestamp. Trashed snapshots are auto-purged after 30 days via `cleanUpOldTrash()`, called on app launch.

**URL-based diffing** — Snapshot comparison matches tabs by URL (case-insensitive), categorizing them as added, removed, or common. This is a pure function with no SwiftData dependency.

**Accessibility** — All interactive elements have `.accessibilityLabel()` and `.accessibilityHint()` for VoiceOver compatibility.

## Development

### Building

```bash
swift build
swift build -c release   # Release build
```

### Testing

```bash
# Run all tests (94 tests across 10 suites)
swift test

# Run a specific test suite
swift test --filter SnapshotServiceTests
swift test --filter SnapshotExportTests
swift test --filter SyncServiceTests
```

### Code Style

- Swift 6 with strict concurrency checking
- `@MainActor` on all services and view models that interact with SwiftData or AppKit
- `@Observable` for state management (no ObservableObject)
- Swift Testing framework (not XCTest)
- `#Predicate` for SwiftData fetch descriptors
- `@unchecked Sendable` only where absolutely necessary (NSCache, Timer workarounds)

## Test Coverage

The project includes **94 tests across 10 suites**:

| Suite | Tests | What's Covered |
|-------|-------|----------------|
| AutoNamerTests | 10 | Name prefixes, pluralization, date format, edge cases |
| SafariBridgeTests | 18 | Tab model, Codable, error messages, JXA execution |
| SnapshotServiceTests | 27 | CRUD, search (name/URL/title/domain), cascade delete, trash/restore, cleanup |
| SnapshotDiffTests | 8 | URL diffing, case-insensitivity, empty sets, many items |
| SnapshotExportTests | 14 | JSON roundtrip, version validation, service integration |
| SyncServiceTests | 15 | Default state, toggling, cloud availability, status messages |

## License

MIT License — see [LICENSE](LICENSE) for details.
