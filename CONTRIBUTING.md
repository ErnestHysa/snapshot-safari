# Contributing to Snapshot Safari

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to Snapshot Safari.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Coding Guidelines](#coding-guidelines)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)

## Code of Conduct

By participating in this project, you agree to abide by the following:

- **Be respectful** — Treat others with respect and kindness. Disagreement is fine, personal attacks are not.
- **Be constructive** — Focus on improving the project. Provide actionable feedback and suggestions.
- **Be inclusive** — Welcome contributors of all backgrounds and experience levels.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork**:
   ```bash
   git clone https://github.com/your-username/snapshot-safari.git
   cd snapshot-safari
   ```
3. **Set up the development environment** (see [Development Setup](#development-setup))
4. **Create a branch** for your work:
   ```bash
   git checkout -b feature/your-feature-name
   ```
5. **Make your changes** following the [coding guidelines](#coding-guidelines)
6. **Run tests** to ensure nothing is broken
7. **Submit a pull request**

## Development Setup

### Prerequisites

- macOS 15.0 (Sequoia) or later
- Xcode 16+ (for Swift 6.0 support)
- Safari (for running the app and integration tests)

### Building

```bash
# Build the project
swift build

# Build with optimizations (for distribution)
swift build -c release
```

### Running

```bash
# Run from the command line
swift run

# Or open in Xcode
open Package.swift
```

## Project Structure

```
SnapshotSafari/
├── Package.swift                    # SPM manifest (Swift 6.0, macOS 15+)
├── SnapshotSafari.entitlements      # Public build (no iCloud)
├── appcast.xml                      # Sparkle update feed
├── Sources/SnapshotSafari/
│   ├── SnapshotSafariApp.swift      # App entry, commands, CloudKit init
│   ├── Info.plist                   # Bundle metadata, Sparkle keys
│   ├── Resources/
│   │   ├── Assets.xcassets          # App icon, colors
│   │   ├── AppIcon.icns             # Compiled app icon
│   │   └── Entitlements/            # Dual-variant entitlements
│   ├── Models/                      # SwiftData models + Codable exports
│   ├── Services/                    # Business logic (bridge, CRUD, sync, etc.)
│   ├── ViewModels/                  # Observable state for views
│   ├── Utilities/                   # Helpers (AutoNamer)
│   └── Views/                       # SwiftUI views
├── Scripts/
│   ├── build-app.sh                 # swift build → .app bundle
│   ├── generate-icon.py             # SVG → PNGs → AppIcon.icns
│   └── release/                     # DMG, signing, notarization scripts
├── Tests/SnapshotSafariTests/       # 164 tests across 16 suites
```

## Coding Guidelines

### Swift & SwiftUI

- **Swift 6** with full strict concurrency checking enabled
- Use `@MainActor` on all services and view models that interact with SwiftData or AppKit
- Prefer `@Observable` over `ObservableObject` for state management
- Use Swift Testing framework (not XCTest) for tests
- Use `#Predicate` for SwiftData fetch descriptors
- Avoid `@unchecked Sendable` unless absolutely necessary (document why)

### Code Style

- Follow the existing style in the codebase (formatting, naming, patterns)
- Use meaningful names — avoid abbreviations unless they're universally understood
- Add documentation comments (`///`) for all public APIs
- Keep functions focused and small — prefer extraction over inline complexity
- Use SwiftUI's built-in modifiers before custom solutions

### Accessibility

- Add `.accessibilityLabel()` and `.accessibilityHint()` to all interactive elements
- The label should describe the element (e.g., "Export this snapshot")
- The hint should explain the result of interacting (e.g., "Saves this snapshot as a JSON file")
- Use `.accessibilityElement(children: .combine)` for compound elements
- Test with VoiceOver enabled before submitting

### SwiftData

- All SwiftData models should use `@Model` macro
- Use `#Predicate` for filtering and `SortDescriptor` for sorting
- Insert into `ModelContext` before accessing relationship properties
- Use cascade delete rules for parent-child relationships
- Prefer soft-delete (isTrashed flag) over permanent deletion

## Testing

### Running Tests

```bash
# Run all tests
swift test

# Run a specific test suite
swift test --filter SnapshotServiceTests
swift test --filter AutoNamerTests
```

### Test Coverage (164 tests, 16 suites)

| Suite | Tests | Area |
|-------|-------|------|
| BrowserBridgeTests | 18 | BrowserTab model, BrowserBridgeError, JXA |
| SnapshotServiceTests | 27 | CRUD, search, trash, cleanup |
| RestoreServiceTests | 18 | Partial failures, restoreGroups, MockBridge |
| AutoSnapshotTargetTests | 28 | Dynamic targets, migration, filtering |
| SnapshotDiffTests | 8 | URL diffing algorithm |
| SnapshotExportTests | 14 | JSON export/import |
| SyncServiceTests | 19 | iCloud sync state |
| AutoNamerTests | 10 | Snapshot naming logic |
| PermissionsServiceProbeTests | 4 | TCC permission probe |
| SettingsTabTests | 5 | Settings UI |

### Writing Tests

- Use the Swift Testing framework (`@Test`, `#expect`)
- Group related tests in `@MainActor struct` (for SwiftData tests) or plain `struct` (for pure logic tests)
- Use in-memory `ModelConfiguration` for SwiftData tests
- Name tests descriptively — the test function name should describe the expected behavior
- Each test should verify one logical behavior

## Pull Request Process

1. **Ensure tests pass** — run `swift test` before submitting
2. **Keep changes focused** — a PR should address one concern. Split large features into multiple PRs
3. **Write good commit messages**:
   - Use conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `ci:`, `a11y:`
   - Explain *what* and *why*, not just *how*
4. **Update documentation** if your changes affect the API, UI, or build process
5. **Add tests** for new functionality
6. **Update the README** if your changes add or modify features

### Pull Request Checklist

- [ ] Code follows the project's coding guidelines
- [ ] Tests pass locally (`swift test`)
- [ ] New tests added for new functionality
- [ ] Documentation updated (README, comments, etc.)
- [ ] Accessibility labels added for new UI elements
- [ ] Commit messages follow conventional commits format

## Reporting Issues

### Bug Reports

When reporting a bug, please include:

- **Steps to reproduce** — what actions lead to the bug
- **Expected behavior** — what should happen
- **Actual behavior** — what actually happens
- **Environment** — macOS version, Xcode version, app version
- **Screenshots** or crash logs if applicable

### Feature Requests

Feature requests are welcome! Please describe:

- **The problem** you're trying to solve
- **The proposed solution**
- **Alternatives** you've considered

## Release Process

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`
2. Build and sign the release DMG:
   ```bash
   ./Scripts/release/build-release.sh && ./Scripts/release/make-dmg.sh
   ```
3. Sign the DMG with Sparkle's `sign_update` tool
4. Update `appcast.xml` with the new version's metadata + edSignature + DMG URL
5. Tag the release: `git tag v1.0.2 && git push --tags`
6. Create a GitHub Release with the DMG asset
