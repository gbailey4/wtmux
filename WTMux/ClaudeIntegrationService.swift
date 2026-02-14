import Foundation

@MainActor @Observable
final class ClaudeIntegrationService {
    private(set) var claudeCodeInstalled = false
    private(set) var mcpRegistered = false
    private(set) var hooksRegistered = false

    var allEnabled: Bool { mcpRegistered && hooksRegistered }
    var canUseClaudeConfig: Bool { claudeCodeInstalled && mcpRegistered }

    init() {
        checkStatus()
    }

    // MARK: - Status

    func checkStatus() {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let claudeConfig = home.appendingPathComponent(".claude.json")
        claudeCodeInstalled = FileManager.default.fileExists(atPath: claudeConfig.path)
        if claudeCodeInstalled {
            mcpRegistered = isMCPRegistered(in: claudeConfig)
            let settingsConfig = home.appendingPathComponent(".claude/settings.json")
            hooksRegistered = isHooksRegistered(in: settingsConfig)
        } else {
            mcpRegistered = false
            hooksRegistered = false
        }
    }

    // MARK: - Enable / Disable All

    func enableAll() throws {
        if !mcpRegistered { try enableMCP() }
        if !hooksRegistered { try enableHooks() }
    }

    func disableAll() {
        if mcpRegistered { disableMCP() }
        if hooksRegistered { disableHooks() }
    }

    // MARK: - MCP

    func enableMCP() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".claude.json")
        try addMCPRegistration(to: configURL)
        mcpRegistered = true
    }

    func disableMCP() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".claude.json")
        removeMCPRegistration(from: configURL)
        mcpRegistered = false
    }

    // MARK: - Hooks

    func enableHooks() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".claude/settings.json")
        try addHooksRegistration(to: configURL)
        if isHooksRegistered(in: configURL) {
            hooksRegistered = true
        }
    }

    func disableHooks() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".claude/settings.json")
        removeHooksRegistration(from: configURL)
        hooksRegistered = false
    }

    // MARK: - Private Helpers

    private func mcpBinaryPath() -> String {
        if let execURL = Bundle.main.executableURL {
            return execURL.deletingLastPathComponent()
                .appendingPathComponent("wtmux-mcp").path
        }
        return "/Applications/WTMux.app/Contents/MacOS/wtmux-mcp"
    }

    private func addMCPRegistration(to configURL: URL) throws {
        var config: [String: Any] = [:]

        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }

        var mcpServers = config["mcpServers"] as? [String: Any] ?? [:]
        let entry: [String: Any] = [
            "command": mcpBinaryPath(),
            "args": [] as [String],
            "type": "stdio",
        ]
        mcpServers["wtmux"] = entry
        config["mcpServers"] = mcpServers

        let data = try JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configURL, options: .atomic)
    }

    private func removeMCPRegistration(from configURL: URL) {
        guard let data = try? Data(contentsOf: configURL),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var mcpServers = config["mcpServers"] as? [String: Any] else {
            return
        }

        mcpServers.removeValue(forKey: "wtmux")
        config["mcpServers"] = mcpServers

        if let data = try? JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    private func isMCPRegistered(in configURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = config["mcpServers"] as? [String: Any] else {
            return false
        }
        return mcpServers["wtmux"] != nil
    }

    // MARK: - Hooks Registration

    private func hookBinaryPath() -> String {
        if let execURL = Bundle.main.executableURL {
            return execURL.deletingLastPathComponent()
                .appendingPathComponent("wtmux-hook").path
        }
        return "/Applications/WTMux.app/Contents/MacOS/wtmux-hook"
    }

    private func hookEntry() -> [String: Any] {
        [
            "type": "command",
            "command": hookBinaryPath(),
            "async": true,
            "timeout": 5,
        ] as [String: Any]
    }

    private func addHooksRegistration(to configURL: URL) throws {
        var config: [String: Any] = [:]

        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }

        var hooks = config["hooks"] as? [String: Any] ?? [:]
        let entry = hookEntry()

        // Simple event hooks (no matcher)
        for event in ["Stop", "SessionStart", "SessionEnd", "UserPromptSubmit", "PermissionRequest"] {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            // Remove any existing wtmux-hook entries
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

        // Ensure directory exists
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configURL, options: .atomic)
    }

    private func removeHooksRegistration(from configURL: URL) {
        guard let data = try? Data(contentsOf: configURL),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = config["hooks"] as? [String: Any] else {
            return
        }

        for event in ["Stop", "SessionStart", "SessionEnd", "UserPromptSubmit", "PermissionRequest", "Notification"] {
            guard var eventHooks = hooks[event] as? [[String: Any]] else { continue }
            eventHooks.removeAll { group in
                guard let innerHooks = group["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { ($0["command"] as? String)?.contains("wtmux-hook") == true }
            }
            if eventHooks.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = eventHooks
            }
        }

        if hooks.isEmpty {
            config.removeValue(forKey: "hooks")
        } else {
            config["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    private func isHooksRegistered(in configURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = config["hooks"] as? [String: Any],
              let stopHooks = hooks["Stop"] as? [[String: Any]] else {
            return false
        }
        return stopHooks.contains { group in
            guard let innerHooks = group["hooks"] as? [[String: Any]] else { return false }
            return innerHooks.contains { ($0["command"] as? String)?.contains("wtmux-hook") == true }
        }
    }
}
