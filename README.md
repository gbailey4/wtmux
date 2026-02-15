# WTMux

An agent-first worktree manager for macOS. Set up projects through conversation, run multiple worktrees side by side with embedded terminals, and let your coding agents work in parallel.

## Features

### Agent-First Configuration

Configure your entire project through a Claude Code conversation — runners, env files, setup commands. The built-in MCP server auto-detects your stack and suggests the right configuration. Every new worktree comes ready to go with dependencies installed, env files copied, and runners started.

Support is expanding for Codex, OpenCode, and other coding agents.

### Parallel Worktrees

Run multiple worktrees side by side with split panes and drag-and-drop. Each worktree gets its own terminal and runner stack. Create a new worktree from any branch in seconds — no more `git stash` / `git stash pop`.

### Auto-Managed Runners

Runners auto-start when you open a worktree — dev servers, watchers, all of it. Ports are auto-detected so you always know what's running where. Environment files are automatically copied to new worktrees.

### Built-in Diff Viewer

Side-by-side diff viewer with syntax highlighting. See changed files at a glance with per-worktree git status tracking.

## Requirements

- macOS 15.0+

## Building from Source

WTMux uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project.

```bash
# Generate the Xcode project and build
xcodegen generate
xcodebuild -project WTMux.xcodeproj -scheme WTMux -destination "platform=macOS" build
```

Or open `WTMux.xcodeproj` in Xcode after running `xcodegen generate`.

## Architecture

The app is split into local Swift packages under `Packages/`:

| Package | Description |
|---------|-------------|
| **WTCore** | SwiftData models and project service |
| **WTTransport** | Transport protocol abstracting local vs SSH execution |
| **WTGit** | Git CLI operations via the transport layer |
| **WTProcess** | Dev server process management and port allocation |
| **WTTerminal** | Native terminal emulator (SwiftTerm) |
| **WTDiff** | Unified diff parsing and side-by-side viewer |
| **WTMCP** | MCP server for agent integration |

## Running Tests

```bash
# All tests
xcodebuild -project WTMux.xcodeproj -scheme WTMux -destination "platform=macOS" test

# Single package
swift test --package-path Packages/WTCore
```

Tests use the Swift Testing framework.

## License

MIT — see [LICENSE](LICENSE) for details.
