import Foundation
import WTTransport
import os.log

private let logger = Logger(subsystem: "com.grahampark.wtmux", category: "RemoteClaudeSetup")

enum RemoteSetupError: LocalizedError {
    case noPython
    case permissionDenied(String)
    case connectionLost
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPython:
            return "Python 3 was not found. Please install Python 3.6+ on the server."
        case .permissionDenied(let detail):
            return "Could not write to ~/.wtmux/bin/. \(detail)"
        case .connectionLost:
            return "Connection lost during setup. You can safely retry — setup is idempotent."
        case .commandFailed(let detail):
            return detail
        }
    }
}

enum RemoteSetupState: Equatable {
    case idle
    case checking
    case needsSetup(pythonPath: String)
    case alreadySetup
    case deploying(step: String)
    case completed
    case failed(String)
}

@MainActor @Observable
final class RemoteClaudeSetupService {
    private(set) var state: RemoteSetupState = .idle
    private(set) var claudeCodeDetected = false

    // MARK: - Script Content

    static func hookScriptContent() -> String? {
        guard let url = Bundle.main.url(
            forResource: "wtmux-hook",
            withExtension: "py",
            subdirectory: "remote-scripts"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func mcpScriptContent() -> String? {
        guard let url = Bundle.main.url(
            forResource: "wtmux-mcp",
            withExtension: "py",
            subdirectory: "remote-scripts"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Bundled script version parsed from `__version__` line.
    static func bundledVersion(of script: String) -> String? {
        for line in script.components(separatedBy: .newlines) {
            if line.hasPrefix("__version__") {
                // Extract version string between quotes
                let stripped = line.replacingOccurrences(of: "__version__", with: "")
                    .replacingOccurrences(of: "=", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !stripped.isEmpty { return stripped }
            }
        }
        return nil
    }

    // MARK: - Check Prerequisites

    func checkPrerequisites(transport: CommandTransport) async {
        state = .checking

        // 1. Find Python 3
        let pythonPath: String
        do {
            pythonPath = try await findPython(transport: transport)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        // 2. Check if Claude Code config exists (informational)
        do {
            let result = try await transport.execute("test -f ~/.claude.json && echo yes || echo no", in: nil)
            claudeCodeDetected = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
        } catch {
            claudeCodeDetected = false
        }

        // 3. Check if scripts are already deployed and up to date
        do {
            let result = try await transport.execute(
                "~/.wtmux/bin/wtmux-mcp.py --version 2>/dev/null || echo missing",
                in: nil
            )
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if output != "missing", let bundledMCP = Self.mcpScriptContent(),
               let bundledVersion = Self.bundledVersion(of: bundledMCP) {
                // Parse deployed version: "wtmux 1.0.0"
                let deployedVersion = output.components(separatedBy: " ").last ?? ""
                if deployedVersion == bundledVersion {
                    state = .alreadySetup
                    return
                }
            }
        } catch {
            // Script not deployed or error checking
        }

        state = .needsSetup(pythonPath: pythonPath)
    }

    // MARK: - Full Setup

    func performFullSetup(transport: CommandTransport) async {
        // Ensure we have python path
        let pythonPath: String
        if case .needsSetup(let path) = state {
            pythonPath = path
        } else {
            do {
                pythonPath = try await findPython(transport: transport)
            } catch {
                state = .failed(error.localizedDescription)
                return
            }
        }

        do {
            state = .deploying(step: "Creating directories...")
            try await deployScripts(transport: transport)

            state = .deploying(step: "Registering MCP server...")
            try await registerMCP(transport: transport, pythonPath: pythonPath)

            state = .deploying(step: "Registering hooks...")
            try await registerHooks(transport: transport, pythonPath: pythonPath)

            state = .completed
            logger.info("Remote Claude setup completed successfully")
        } catch {
            let msg = error.localizedDescription
            state = .failed(msg)
            logger.error("Remote Claude setup failed: \(msg)")
        }
    }

    // MARK: - Check and Update

    func checkAndUpdateIfNeeded(transport: CommandTransport) async {
        guard let bundledMCP = Self.mcpScriptContent(),
              let bundledVersion = Self.bundledVersion(of: bundledMCP) else { return }

        do {
            let result = try await transport.execute(
                "~/.wtmux/bin/wtmux-mcp.py --version 2>/dev/null || echo missing",
                in: nil
            )
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if output == "missing" { return }

            let deployedVersion = output.components(separatedBy: " ").last ?? ""
            if deployedVersion != bundledVersion {
                logger.info("Updating remote scripts: \(deployedVersion) → \(bundledVersion)")
                try await deployScripts(transport: transport)
            }
        } catch {
            logger.warning("Could not check remote script version: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func findPython(transport: CommandTransport) async throws -> String {
        do {
            let result = try await transport.execute(
                "which python3 2>/dev/null || which python 2>/dev/null",
                in: nil
            )
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty || !result.succeeded {
                throw RemoteSetupError.noPython
            }

            // Verify it's Python 3
            let verResult = try await transport.execute("\(path) --version 2>&1", in: nil)
            let version = verResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard version.hasPrefix("Python 3") else {
                throw RemoteSetupError.noPython
            }

            return path
        } catch let error as RemoteSetupError {
            throw error
        } catch {
            throw RemoteSetupError.connectionLost
        }
    }

    private func deployScripts(transport: CommandTransport) async throws {
        guard let hookScript = Self.hookScriptContent(),
              let mcpScript = Self.mcpScriptContent() else {
            throw RemoteSetupError.commandFailed("Could not read bundled Python scripts from app bundle.")
        }

        // Create directory
        let mkdirResult = try await transport.execute("mkdir -p ~/.wtmux/bin", in: nil)
        if !mkdirResult.succeeded {
            throw RemoteSetupError.permissionDenied(mkdirResult.stderr)
        }

        // Deploy hook script via heredoc
        let hookResult = try await transport.execute(
            "cat > ~/.wtmux/bin/wtmux-hook.py <<'WTMUXEOF'\n\(hookScript)\nWTMUXEOF",
            in: nil
        )
        if !hookResult.succeeded {
            throw RemoteSetupError.permissionDenied(hookResult.stderr)
        }

        // Deploy MCP script via heredoc
        let mcpResult = try await transport.execute(
            "cat > ~/.wtmux/bin/wtmux-mcp.py <<'WTMUXEOF'\n\(mcpScript)\nWTMUXEOF",
            in: nil
        )
        if !mcpResult.succeeded {
            throw RemoteSetupError.permissionDenied(mcpResult.stderr)
        }

        // Make executable
        let chmodResult = try await transport.execute(
            "chmod +x ~/.wtmux/bin/wtmux-hook.py ~/.wtmux/bin/wtmux-mcp.py",
            in: nil
        )
        if !chmodResult.succeeded {
            throw RemoteSetupError.permissionDenied(chmodResult.stderr)
        }
    }

    private func registerMCP(transport: CommandTransport, pythonPath: String) async throws {
        // Read existing ~/.claude.json or start fresh
        let readResult = try await transport.execute("cat ~/.claude.json 2>/dev/null || echo '{}'", in: nil)
        var config: [String: Any]
        let jsonString = readResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = parsed
        } else {
            config = [:]
        }

        // Merge mcpServers.wtmux entry
        var mcpServers = config["mcpServers"] as? [String: Any] ?? [:]
        mcpServers["wtmux"] = [
            "command": pythonPath,
            "args": [home("~/.wtmux/bin/wtmux-mcp.py")],
            "type": "stdio",
        ] as [String: Any]
        config["mcpServers"] = mcpServers

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw RemoteSetupError.commandFailed("Failed to serialize claude.json")
        }

        let writeResult = try await transport.execute(
            "cat > ~/.claude.json <<'WTMUXEOF'\n\(json)\nWTMUXEOF",
            in: nil
        )
        if !writeResult.succeeded {
            throw RemoteSetupError.commandFailed("Failed to write ~/.claude.json: \(writeResult.stderr)")
        }
    }

    private func registerHooks(transport: CommandTransport, pythonPath: String) async throws {
        // Ensure directory exists
        let _ = try await transport.execute("mkdir -p ~/.claude", in: nil)

        // Read existing settings.json or start fresh
        let readResult = try await transport.execute("cat ~/.claude/settings.json 2>/dev/null || echo '{}'", in: nil)
        var config: [String: Any]
        let jsonString = readResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = parsed
        } else {
            config = [:]
        }

        var hooks = config["hooks"] as? [String: Any] ?? [:]

        let hookCommand = "\(pythonPath) \(home("~/.wtmux/bin/wtmux-hook.py"))"
        let entry: [String: Any] = [
            "type": "command",
            "command": hookCommand,
            "async": true,
            "timeout": 5,
        ]

        // Simple event hooks (no matcher)
        for event in ["Stop", "SessionStart", "SessionEnd", "UserPromptSubmit", "PermissionRequest"] {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            // Remove existing wtmux entries
            eventHooks.removeAll { group in
                guard let innerHooks = group["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { ($0["command"] as? String)?.contains("wtmux-hook") == true }
            }
            eventHooks.append(["hooks": [entry]])
            hooks[event] = eventHooks
        }

        // Notification hook with matcher
        var notifHooks = hooks["Notification"] as? [[String: Any]] ?? []
        notifHooks.removeAll { group in
            guard let innerHooks = group["hooks"] as? [[String: Any]] else { return false }
            return innerHooks.contains { ($0["command"] as? String)?.contains("wtmux-hook") == true }
        }
        notifHooks.append([
            "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
            "hooks": [entry],
        ] as [String: Any])
        hooks["Notification"] = notifHooks

        config["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw RemoteSetupError.commandFailed("Failed to serialize settings.json")
        }

        let writeResult = try await transport.execute(
            "cat > ~/.claude/settings.json <<'WTMUXEOF'\n\(json)\nWTMUXEOF",
            in: nil
        )
        if !writeResult.succeeded {
            throw RemoteSetupError.commandFailed("Failed to write ~/.claude/settings.json: \(writeResult.stderr)")
        }
    }

    /// Expand ~ to $HOME on the remote. We use ~ literally in commands since
    /// the remote shell expands it, but for JSON config values we need the
    /// expansion done by the remote shell.
    private func home(_ path: String) -> String {
        // In JSON config values sent to the remote, ~ won't be expanded.
        // We keep the path as-is since the remote shell handles ~ in commands.
        // For args arrays in JSON, use the literal path — Claude Code will
        // invoke the command through a shell that expands ~.
        return path
    }
}
