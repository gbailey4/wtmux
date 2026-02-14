import SwiftUI
import UniformTypeIdentifiers
import WTLLM
import WTTerminal

struct SettingsView: View {
    @AppStorage("defaultShell") private var defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    @AppStorage("terminalFontSize") private var terminalFontSize = 13.0
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id

    @AppStorage("llmModel") private var llmModel = "claude-sonnet-4-5-20250929"
    @State private var apiKeyInput = ""
    @State private var apiKeyStatus: APIKeyStatus = .unknown
    @State private var isVerifying = false

    @State private var customEditors = ExternalEditor.customEditors
    @State private var hiddenEditorIds = ExternalEditor.hiddenEditorIds

    @State private var claudeCodeInstalled = false
    @State private var claudeCodeEnabled = false
    @State private var claudeHooksEnabled = false
    @State private var cursorInstalled = false
    @State private var cursorEnabled = false
    @State private var agentMessage: String?

    private var allEditors: [ExternalEditor] {
        ExternalEditor.installedEditors(custom: customEditors, hidden: hiddenEditorIds)
    }

    var body: some View {
        Form {
            Section("Terminal") {
                HStack {
                    TextField("Default Shell", text: $defaultShell)
                        .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                        browseShell()
                    }
                }

                HStack {
                    Text("Font Size")
                    Slider(value: $terminalFontSize, in: 10...24, step: 1)
                    Text("\(Int(terminalFontSize))pt")
                        .monospacedDigit()
                }

                HStack {
                    Text("Theme")
                    Picker("Theme", selection: $terminalThemeId) {
                        ForEach(TerminalThemes.allThemes) { theme in
                            HStack(spacing: 8) {
                                ThemeSwatchView(theme: theme)
                                Text(theme.name)
                            }
                            .tag(theme.id)
                        }
                    }
                }
            }

            Section("AI") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude API Key")
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                        Button(apiKeyStatus == .valid ? "Verified" : "Verify") {
                            verifyAPIKey()
                        }
                        .disabled(apiKeyInput.isEmpty || isVerifying)
                    }
                    if case .invalid(let message) = apiKeyStatus {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if apiKeyStatus == .valid {
                        Text("API key is valid")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .foregroundStyle(.secondary)
                    TextField("", text: $llmModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Text("Default: claude-sonnet-4-5-20250929")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Editors") {
                ForEach(allEditors) { editor in
                    HStack(spacing: 10) {
                        if let icon = editor.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app.dashed")
                                .frame(width: 24, height: 24)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(editor.name)
                            Text(editor.bundleId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            removeEditor(editor)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Editor...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url,
                       let editor = ExternalEditor.fromAppBundle(at: url) {
                        guard !customEditors.contains(where: { $0.bundleId == editor.bundleId }) else { return }
                        customEditors.append(editor)
                        ExternalEditor.customEditors = customEditors
                    }
                }
            }

            Section("Agent Integration") {
                agentRow(
                    name: "Claude Code",
                    icon: "terminal.fill",
                    installed: claudeCodeInstalled,
                    enabled: claudeCodeEnabled
                ) { toggleClaudeCode() }

                agentRow(
                    name: "Claude Code Status",
                    icon: "bell.badge",
                    installed: claudeCodeInstalled,
                    enabled: claudeHooksEnabled
                ) { toggleClaudeHooks() }

                agentRow(
                    name: "Cursor",
                    icon: "cursorarrow.rays",
                    installed: cursorInstalled,
                    enabled: cursorEnabled
                ) { toggleCursor() }

                if let agentMessage {
                    Text(agentMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .labelsHidden()
        .frame(width: 450)
        .navigationTitle("Settings")
        .onAppear {
            if let key = KeychainStore.loadAPIKey(for: .claude) {
                apiKeyInput = key
            }
            checkAgentStatus()
        }
        .onChange(of: apiKeyInput) {
            apiKeyStatus = .unknown
        }
    }

    private func browseShell() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a shell executable"
        let currentShellURL = URL(fileURLWithPath: defaultShell)
        panel.directoryURL = currentShellURL.deletingLastPathComponent()

        if panel.runModal() == .OK, let url = panel.url {
            defaultShell = url.path
        }
    }

    private func verifyAPIKey() {
        guard !apiKeyInput.isEmpty else { return }
        isVerifying = true
        apiKeyStatus = .unknown

        // Save the key first
        try? KeychainStore.saveAPIKey(apiKeyInput, for: .claude)

        Task {
            let provider = ClaudeProvider(apiKey: apiKeyInput, model: llmModel)
            let tool = PromptBuilder.analysisToolDefinition()

            do {
                _ = try await provider.analyzeWithTool(
                    systemPrompt: "You are a test. Respond with empty analysis.",
                    userMessage: "Test connection. Return empty arrays.",
                    tool: tool,
                    timeout: 15
                )
                apiKeyStatus = .valid
            } catch let error as LLMError {
                switch error {
                case .noAPIKey:
                    apiKeyStatus = .invalid(message: "Invalid API key")
                case .networkError(let detail):
                    apiKeyStatus = .invalid(message: "Network error: \(detail)")
                case .rateLimited:
                    // Rate limited means the key is valid
                    apiKeyStatus = .valid
                case .timeout:
                    apiKeyStatus = .invalid(message: "Request timed out")
                case .invalidResponse:
                    // Got a response, key works
                    apiKeyStatus = .valid
                }
            } catch {
                apiKeyStatus = .invalid(message: error.localizedDescription)
            }
            isVerifying = false
        }
    }

    private func removeEditor(_ editor: ExternalEditor) {
        if let index = customEditors.firstIndex(where: { $0.bundleId == editor.bundleId }) {
            customEditors.remove(at: index)
            ExternalEditor.customEditors = customEditors
        } else {
            hiddenEditorIds.insert(editor.bundleId)
            ExternalEditor.hiddenEditorIds = hiddenEditorIds
        }
    }

    // MARK: - Agent Integration

    @ViewBuilder
    private func agentRow(
        name: String,
        icon: String,
        installed: Bool,
        enabled: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if !installed {
                    Text("Not detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if enabled {
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if installed {
                Button(enabled ? "Disable" : "Enable") {
                    onToggle()
                }
            }
        }
    }

    private func checkAgentStatus() {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let claudeConfig = home.appendingPathComponent(".claude.json")
        claudeCodeInstalled = FileManager.default.fileExists(atPath: claudeConfig.path)
        if claudeCodeInstalled {
            claudeCodeEnabled = isMCPRegistered(in: claudeConfig)
            let settingsConfig = home.appendingPathComponent(".claude/settings.json")
            claudeHooksEnabled = isHooksRegistered(in: settingsConfig)
        }

        let cursorDir = home.appendingPathComponent(".cursor")
        cursorInstalled = FileManager.default.fileExists(atPath: cursorDir.path)
        if cursorInstalled {
            let cursorConfig = cursorDir.appendingPathComponent("mcp.json")
            cursorEnabled = isMCPRegistered(in: cursorConfig)
        }
    }

    private func toggleClaudeCode() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".claude.json")

        if claudeCodeEnabled {
            removeMCPRegistration(from: configURL)
            claudeCodeEnabled = false
            agentMessage = nil
        } else {
            addMCPRegistration(to: configURL, includeType: true)
            claudeCodeEnabled = true
            agentMessage = "Restart Claude Code to activate"
        }
    }

    private func toggleCursor() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cursorDir = home.appendingPathComponent(".cursor")
        let configURL = cursorDir.appendingPathComponent("mcp.json")

        if cursorEnabled {
            removeMCPRegistration(from: configURL)
            cursorEnabled = false
            agentMessage = nil
        } else {
            try? FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
            addMCPRegistration(to: configURL, includeType: false)
            cursorEnabled = true
            agentMessage = "Restart Cursor to activate"
        }
    }

    private func toggleClaudeHooks() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".claude/settings.json")

        if claudeHooksEnabled {
            removeHooksRegistration(from: configURL)
            claudeHooksEnabled = false
            agentMessage = nil
        } else {
            do {
                try addHooksRegistration(to: configURL)
                // Verify hooks were actually written
                if isHooksRegistered(in: configURL) {
                    claudeHooksEnabled = true
                    agentMessage = "Restart Claude Code to activate status hooks"
                } else {
                    agentMessage = "Failed to verify hooks in settings file"
                }
            } catch {
                agentMessage = "Failed to write hooks: \(error.localizedDescription)"
            }
        }
    }

    private func mcpBinaryPath() -> String {
        if let execURL = Bundle.main.executableURL {
            return execURL.deletingLastPathComponent()
                .appendingPathComponent("wtmux-mcp").path
        }
        return "/Applications/WTMux.app/Contents/MacOS/wtmux-mcp"
    }

    private func addMCPRegistration(to configURL: URL, includeType: Bool) {
        var config: [String: Any] = [:]

        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }

        var mcpServers = config["mcpServers"] as? [String: Any] ?? [:]
        var entry: [String: Any] = [
            "command": mcpBinaryPath(),
            "args": [] as [String],
        ]
        if includeType {
            entry["type"] = "stdio"
        }
        mcpServers["wtmux"] = entry
        config["mcpServers"] = mcpServers

        if let data = try? JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: configURL, options: .atomic)
        }
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

private enum APIKeyStatus: Equatable {
    case unknown
    case valid
    case invalid(message: String)
}

private struct ThemeSwatchView: View {
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 1) {
            Rectangle()
                .fill(Color(nsColor: theme.background.toNSColor()))
            Rectangle()
                .fill(Color(nsColor: theme.foreground.toNSColor()))
            Rectangle()
                .fill(Color(nsColor: theme.ansiColors[1].toNSColor())) // red
            Rectangle()
                .fill(Color(nsColor: theme.ansiColors[2].toNSColor())) // green
            Rectangle()
                .fill(Color(nsColor: theme.ansiColors[4].toNSColor())) // blue
        }
        .frame(width: 60, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}
