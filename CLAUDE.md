# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

This project uses XcodeGen to generate the Xcode project from `project.yml`. After any changes to project structure, targets, or dependencies:

```bash
xcodegen generate
```

Full build:

```bash
xcodegen generate && xcodebuild -project WTMux.xcodeproj -scheme WTMux -destination "platform=macOS" build
```

## Test

Run all tests across all packages:

```bash
xcodebuild -project WTMux.xcodeproj -scheme WTMux -destination "platform=macOS" test
```

Run tests for a single package:

```bash
swift test --package-path Packages/WTCore
```

Tests use the Swift Testing framework (`@Test`, `#expect`).

## Architecture

WTMux is a macOS SwiftUI app for managing git worktrees with embedded terminals. The app is split into 6 local SPM packages under `Packages/`:

- **WTCore** — SwiftData models (`Project`, `Worktree`, `ProjectProfile`, `RunConfiguration`) and `ProjectService`
- **WTTransport** — `CommandTransport` protocol abstracting local vs SSH command execution; `LocalTransport` implementation
- **WTGit** — `GitService` actor wrapping git CLI operations via `CommandTransport`
- **WTProcess** — `ProcessManager` actor for managing long-running dev server processes and port allocation
- **WTTerminal** — `TerminalRepresentable` (NSViewRepresentable wrapping SwiftTerm's `LocalProcessTerminalView`) and `TerminalSessionManager`
- **WTDiff** — `DiffParser` and `SideBySideDiffView` for unified diff visualization

The main app target (`WTMux/`) contains the SwiftUI views organized by feature: `Sidebar/`, `Detail/`, `Interview/` (project setup wizard), `Settings/`, and `Diff/`.

### Key design patterns

- **Transport abstraction:** All git/shell operations go through `CommandTransport` so the same code works for local and remote (SSH) repositories
- **Actor isolation:** `GitService` and `ProcessManager` are actors; strict concurrency checking is enabled (`SWIFT_STRICT_CONCURRENCY: complete`)
- **SwiftData persistence:** Models use `@Model` macro with cascade delete relationships (Project → Worktrees, Project → ProjectProfile → RunConfigurations)

## VS Code / Cursor LSP Setup

After generating the Xcode project and building, run:

```bash
xcode-build-server config -project WTMux.xcodeproj -scheme WTMux
```

This creates `buildServer.json` which tells SourceKit-LSP to use the Xcode build system for module resolution. Re-run after `xcodegen generate` + build if module imports stop resolving.

## Configuration

- Swift 6.0, macOS 15.0+, no app sandbox, no hardened runtime
- XcodeGen config: `project.yml` — requires `path` field on `info` and `entitlements` sections
- External dependencies: HighlightSwift (syntax highlighting), SwiftTerm (native terminal emulator)
