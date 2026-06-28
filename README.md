# Snapshot Safari

> Save and restore your browser tabs across Safari, Chrome, Brave, Edge, Opera, Vivaldi, Orion, Arc, and Firefox — free up RAM without losing anything.

<p align="center">
  <img src="Resources/screenshot.png" alt="Snapshot Safari main window" width="800">
</p>

Snapshot Safari is a native macOS app that captures all your open browser tabs into named snapshots, lets you restore them later in new or current windows, compare changes between snapshots, and automate the process on a schedule.

Built with **SwiftUI**, **SwiftData**, and **Sparkle**.

## Features

### 📸 Multi-Browser Snapshot Management

- **Take snapshots** from any supported browser — ⌘N captures the frontmost browser, ⌘⇧N captures all running browsers at once
- **9 supported browsers** — Safari, Chrome, Brave, Edge, Opera, Vivaldi, Orion, Arc, and Firefox
- **Per-browser tabs** — every tab remembers which browser it came from and restores to the correct browser by default
- **Auto-naming** — snapshots are automatically named with date, tab count, and browser name
- **Search** — find snapshots by name, URL, tab title, or domain
- **Browser filter** — filter the snapshot list to show only Chrome snapshots, only Capture All snapshots, or all
- **Rename** — give snapshots meaningful names
- **Delete with undo** — snapshots go to trash and are auto-cleaned after 30 days
- **Export/Import** — share snapshots as JSON files (⌘E export, ⌘I import)

<p align="center">
  <img src="Resources/screenshot-trash.png" alt="Trash view with recently deleted snapshots" width="700">
</p>

<p align="center">
  <img src="Resources/screenshot-settings.png" alt="Settings panel with auto-snapshot configuration" width="700">
</p>

### 🔄 Tab Restore

- **Restore all tabs** or select specific tabs to restore
- **Browser-aware restore** — tabs restore to their original browser by default, or pick a different target browser
- **Choose restore mode** — open in a new window or append to the current window
- **Partial failure surfacing** — if some browser tabs fail to restore, you'll see exactly which browsers and why
- **Tab preview** — see favicons, URLs, domains, and browser badges for every tab in a snapshot

### ⏰ Auto-Snapshots

- **Scheduled snapshots** — automatically capture tabs every 30 min, 1h, 2h, or 4h
- **Dynamic targets** — auto-snapshot can target any installed readable browser, all running browsers, or the frontmost
- **Custom intervals** — set any interval (minimum 5 minutes)
- **Persistent settings** — auto-snapshot state and interval survive app restarts
- **Silent failures** — auto-snapshots fail gracefully when the target browser isn't running

### ☁️ iCloud Sync

- **Sync across Macs** — share snapshots via iCloud (requires Apple Developer Program)
- **Persistent preference** — sync toggle survives app restarts
- **Graceful fallback** — if CloudKit isn't available, the app uses local storage

### 🎨 Appearance

- **Light, Dark, and System themes** — follow your macOS preference or choose manually
- **Colored browser badges** — each browser gets a distinct brand-colored pill badge for instant visual scanning

### 🔄 Auto-Updates

- **Sparkle-powered updates** — automatic update checks and downloads
- **Check for Updates** menu item in the app menu

## Requirements

- macOS 15.0 (Sequoia) or later
- One or more supported browsers (Safari, Chrome, Brave, Edge, Opera, Vivaldi, Orion) for reading and restoring tabs
- Automation permission for each browser (prompted on first use)

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/ErnestHysa/snapshot-safari.git
cd snapshot-safari

# Build and run
swift run

# Or open in Xcode
open Package.swift
```

### Building for Distribution

The release pipeline is split into two flavors:

**Public release** — what end users download from GitHub releases:

```bash
# Builds an ad-hoc-signed .app that launches on any Mac without a developer account.
./Scripts/build-app.sh release

# Bundle the .app into a versioned DMG with SHA256 checksum.
./Scripts/release/make-dmg.sh

# Verify the DMG: bundle structure, codesign verify (deep + strict),
# Info.plist drift check, privileged-entitlement audit, launchability test.
./Scripts/release/verify-release.sh Release/SnapshotSafari-1.1.0-5.dmg
```

The public release **does not include iCloud / CloudKit entitlements** because
those entitlements require a Developer ID signature and would cause AMFI to
SIGKILL the binary on launch if requested under ad-hoc signing. The iCloud
Sync feature is present in the code, but its toggle is disabled in Settings
for the public build and the user is shown a clear explanation.

**Signed release** — requires an Apple Developer ID ($99/yr):

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
./Scripts/release/sign-app.sh
./Scripts/release/make-dmg.sh
export NOTARY_PROFILE="my-profile"  # configured once via `xcrun notarytool store-credentials`
./Scripts/release/notarize-dmg.sh Release/SnapshotSafari-1.1.0-5.dmg
./Scripts/release/staple-and-verify.sh Release/SnapshotSafari-1.1.0-5.dmg
RELEASE_STRICT=1 ./Scripts/release/verify-release.sh Release/SnapshotSafari-1.1.0-5.dmg
```

**Developer build with iCloud sync** — opt-in iCloud entitlements for personal use:

```bash
ENABLE_ICLOUD_SYNC=1 ./Scripts/build-app.sh
```

The resulting .app requests iCloud / CloudKit entitlements. You must sign it
with a Developer ID (`sign-app.sh` does this) for AMFI to accept it. An
ad-hoc + iCloud entitlement binary is killed by AMFI at launch.

## Setup

### First Launch

1. Open the app — a welcome screen explains what Snapshot Safari does
2. Grant **Automation access** to each browser when prompted (System Settings → Privacy & Security → Automation)
3. Take your first snapshot with ⌘N or the camera button in the toolbar

### Sparkle Auto-Updates

Sparkle is already wired into the app (the `Sparkle` SwiftPM dependency,
`SPUStandardUpdaterController` in `SparkleUpdater.swift`, and
`SUPublicEDKey` + `SUFeedURL` in `Info.plist`). Sparkle checks
`appcast.xml` on the `main` branch, compares the `sparkle:version` (build
number) against the local `CFBundleVersion`, and if a newer version is found,
downloads the DMG from the GitHub release URL after validating the EdDSA
signature.

To publish a new version:

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`
2. Build the new DMG: `./Scripts/release/build-release.sh && ./Scripts/release/make-dmg.sh`
3. Sign the DMG with `Sparkle/bin/sign_update` (the private key is in your macOS Keychain — generated once with `generate_keys`)
4. Replace `REPLACE_WITH_DMG_BYTES` and `REPLACE_WITH_SIGN_UPDATE_OUTPUT` in `appcast.xml` with the file size and EdDSA signature
5. Commit `appcast.xml`, push to `main`, create the GitHub release with the DMG asset

### iCloud Sync

iCloud Sync is fully implemented but **disabled in the public download** because
the CloudKit container + iCloud services entitlements require a Developer ID
signature — Apple Mobile File Integrity (AMFI) kills ad-hoc binaries that
request them.

The app detects at runtime whether the running binary carries the iCloud
entitlements (via `SecTaskCopyValueForEntitlement` in `SyncService.swift`)
and disables the toggle in Settings with an explanation when they are absent.

To enable iCloud sync for personal use:

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/)
2. Create a CloudKit container with identifier `iCloud.com.ernest.snapshot-safari`
   on the [Developer Portal](https://developer.apple.com/account/resources/identifiers/container)
3. Build with iCloud entitlements: `ENABLE_ICLOUD_SYNC=1 ./Scripts/build-app.sh`
4. Sign with your Developer ID: `./Scripts/release/sign-app.sh`
5. The Settings → Sync tab will show iCloud Sync as enabled

## Usage

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | Capture frontmost browser |
| ⌘⇧N | Capture all running browsers |
| ⌘I | Import snapshots from a JSON file |
| ⌘E | Export the selected snapshot |
| ⇧⌘E | Export all snapshots |
| ⌘, | Open settings |
| ⌘⌫ | Delete the selected snapshot |
| ⌘F | Focus search field (sidebar) |
| Escape | Close sheets / dialogs |

### Taking a Snapshot

1. Make sure your browser(s) are running with open tabs
2. Press ⌘N to capture the frontmost browser, or ⌘⇧N to capture all running browsers
3. Use the toolbar camera menu to capture a specific browser
4. The snapshot appears in the sidebar with an auto-generated name and browser badges

### Restoring Tabs

1. Select a snapshot in the sidebar
2. In the detail view, click **Restore All** or select specific tabs and click **Restore Selected**
3. Choose whether to open tabs in a **New Window** or the **Current Window**
4. By default, tabs restore to their original browser — use the browser picker to target a different browser

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
| Browser Integration | JXA via `osascript` (JavaScript for Automation) — WebKit + Chromium |
| Auto-Updates | Sparkle 2.x |
| iCloud Sync | CloudKit (via SwiftData) |
| Minimum OS | macOS 15.0 Sequoia |

### Project Structure

```
SnapshotSafari/
├── Package.swift                              # SPM manifest
├── appcast.xml                                # Sparkle update feed
├── Sources/SnapshotSafari/
│   ├── SnapshotSafariApp.swift                # App entry point, commands, CloudKit init
│   ├── Info.plist                             # Bundle metadata, Sparkle keys
│   ├── Resources/
│   │   ├── Assets.xcassets                    # App icon, colors
│   │   └── Entitlements/
│   │       ├── SnapshotSafari.entitlements       # Public build (no iCloud)
│   │       └── SnapshotSafari.entitlements.dev   # Developer build (with iCloud)
│   ├── Models/
│   │   ├── Browser.swift                      # 9-browser enum: bundle IDs, brand colors, runtime state
│   │   ├── Snapshot.swift                     # SwiftData model: snapshot with tabs
│   │   ├── TabEntry.swift                     # SwiftData model: browser-tagged tab
│   │   ├── SnapshotDiff.swift                 # Diff computation between snapshots
│   │   └── SnapshotExport.swift               # Codable export/import format
│   ├── Services/
│   │   ├── BrowserBridge.swift                # Protocol + WebKitBridge, ChromiumBridge, UnscriptableBridge
│   │   ├── SnapshotService.swift              # Multi-browser capture/restore, CRUD, search, trash
│   │   ├── AutoSnapshotManager.swift          # Dynamic browser-target auto-snapshot loop
│   │   ├── PermissionsService.swift           # Per-browser Automation permission check
│   │   ├── SyncService.swift                  # iCloud sync state + runtime entitlement check
│   │   ├── FaviconService.swift               # Cached favicon fetching
│   │   └── SparkleUpdater.swift               # Auto-update orchestration
│   ├── ViewModels/
│   │   └── SnapshotListViewModel.swift        # Observable state: filters, capture, restore, export
│   ├── Utilities/
│   │   └── AutoNamer.swift                    # Smart snapshot name generation with browser names
│   └── Views/
│       ├── ContentView.swift                  # Root view: split navigation + toolbar with capture menu
│       ├── SnapshotListView.swift             # Sidebar list with browser filter picker
│       ├── SnapshotCard.swift                 # List item with Capture All badge + browser pills
│       ├── SnapshotDetailView.swift           # Tab list + browser-aware restore/export/delete
│       ├── TabRow.swift                       # Individual tab row with colored browser badge
│       ├── RestoreOptionsSheet.swift          # Restore mode + browser target picker
│       ├── CompareSnapshotsView.swift         # Visual diff display
│       ├── TrashView.swift                    # Recently deleted snapshots
│       ├── SettingsView.swift                 # Multi-browser permissions + auto-snapshot settings
│       └── WelcomeView.swift                  # First-launch onboarding
├── Scripts/
│   ├── build-app.sh                           # swift build → .app bundle → codesign
│   ├── generate-icon.py                       # SVG → PNGs → AppIcon.icns
│   └── release/
│       ├── build-release.sh                   # swift test + build-app.sh + stage
│       ├── sign-app.sh                        # Developer ID sign + Hardened Runtime
│       ├── make-dmg.sh                        # Compressed read-only DMG via hdiutil
│       ├── notarize-dmg.sh                    # notarytool submit --wait
│       ├── staple-and-verify.sh               # stapler staple + spctl + codesign
│       └── verify-release.sh                  # Bundle/codesign/entitlements/plist checks
└── Tests/SnapshotSafariTests/
    ├── BrowserBridgeTests.swift               # BrowserTab, BrowserBridgeError, JXA execution tests
    ├── SnapshotServiceTests.swift             # CRUD, search, trash, cleanup tests
    ├── RestoreServiceTests.swift              # RestorePartialFailure, restoreGroups with MockBridge
    ├── AutoSnapshotTargetTests.swift          # Dynamic target resolution, migration, installed browsers
    ├── SnapshotDiffTests.swift                # Diff algorithm tests
    ├── SnapshotExportTests.swift              # Export/import tests
    ├── SyncServiceTests.swift                 # Sync state + entitlement tests
    ├── AutoNamerTests.swift                   # Naming tests
    ├── PermissionsServiceProbeTests.swift     # TCC permission probe tests
    └── SettingsTabTests.swift                 # Settings UI tests
```

### Key Design Decisions

**Abstracted browser bridge** — A `BrowserBridge` protocol with `WebKitBridge`, `ChromiumBridge`, and `UnscriptableBridge` implementations. All Chromium browsers (Chrome, Brave, Edge, Opera, Vivaldi) share identical JXA scripts — only the bundle ID changes. This is handled via a `BrowserBridgeFactory` that selects the right engine.

**Browser-tagged tabs** — Each `TabEntry` carries a `browserId` (the browser's bundle identifier) so tabs remember their origin. Restore dispatches tabs to their original browsers by default, with a dropdown to override.

**SwiftData for persistence** — The app uses SwiftData's `@Model` macros with an in-memory fallback container if local persistence fails. CloudKit sync is conditionally enabled via `ModelConfiguration.cloudKitDatabase`.

**JXA via osascript** — Browser tabs are read and restored using JavaScript for Automation (JXA) scripts executed through `osascript`. This approach works across WebKit and Chromium browsers and returns structured JSON.

**Soft-delete trash** — Snapshots are soft-deleted with an `isTrashed` flag and `deletedAt` timestamp. Trashed snapshots are auto-purged after 30 days via `cleanUpOldTrash()`, called on app launch.

**URL-based diffing** — Snapshot comparison matches tabs by URL (case-insensitive), categorizing them as added, removed, or common.

**Dependency injection for testing** — `SnapshotService.init` accepts a `bridgeProvider` closure (defaulting to `BrowserBridgeFactory.create`), enabling `MockBridge` injection for testing capture/restore error paths.

**Partial failure surfacing** — `CapturePartialFailure` and `RestorePartialFailure` error types carry per-browser success/failure details so the UI can show exactly what succeeded and what failed.

## Development

### Building

```bash
swift build
swift build -c release   # Release build
```

### Testing

```bash
# Run all tests (164 tests across 16 suites)
swift test

# Run a specific test suite
swift test --filter SnapshotServiceTests
swift test --filter RestoreServiceTests
swift test --filter BrowserBridgeTests
```

### Code Style

- Swift 6 with strict concurrency checking
- `@MainActor` on all services and view models that interact with SwiftData or AppKit
- `@Observable` for state management (no ObservableObject)
- Swift Testing framework (not XCTest)
- `#Predicate` for SwiftData fetch descriptors
- `@unchecked Sendable` only where absolutely necessary

## Test Coverage

The project includes **164 tests across 16 suites**:

| Suite | Tests | What's Covered |
|-------|-------|----------------|
| BrowserBridgeTests | 18 | BrowserTab model, BrowserBridgeError, JXA execution |
| SnapshotServiceTests | 27 | CRUD, search, cascade delete, trash/restore, cleanup |
| RestoreServiceTests | 18 | RestorePartialFailure, restoreGroups with MockBridge |
| AutoSnapshotTargetTests | 28 | Dynamic targets, migration, browser filtering |
| SnapshotDiffTests | 8 | URL diffing, case-insensitivity, empty sets |
| SnapshotExportTests | 14 | JSON roundtrip, version validation |
| SyncServiceTests | 19 | Default state, toggling, cloud availability |
| AutoNamerTests | 10 | Name prefixes, pluralization, date format |
| PermissionsServiceProbeTests | 4 | TCC permission probe |
| SettingsTabTests | 5 | Settings UI tabs |

## License

MIT License — see [LICENSE](LICENSE) for details.
