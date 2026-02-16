import SwiftUI
import UniformTypeIdentifiers
import WTTerminal

struct SettingsView: View {
    @AppStorage("defaultShell") private var defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    @AppStorage("terminalFontSize") private var terminalFontSize = 13.0
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id

    @State private var customEditors = ExternalEditor.customEditors
    @State private var hiddenEditorIds = ExternalEditor.hiddenEditorIds

    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @State private var agentMessage: String?

    private var allEditors: [ExternalEditor] {
        ExternalEditor.installedEditors(custom: customEditors, hidden: hiddenEditorIds)
    }

    var body: some View {
        Form {
            Section("Agent Integration") {
                if claudeIntegrationService.claudeCodeInstalled {
                    HStack {
                        Image(systemName: "terminal.fill")
                            .frame(width: 24, height: 24)
                        Text("Claude Code")
                        Spacer()
                        Button(claudeIntegrationService.allEnabled ? "Disable All" : "Enable All") {
                            toggleAllClaude()
                        }
                    }

                    agentSubRow(
                        name: "Project Config (MCP)",
                        enabled: claudeIntegrationService.mcpRegistered
                    ) { toggleClaudeCode() }

                    agentSubRow(
                        name: "Status Monitoring",
                        enabled: claudeIntegrationService.hooksRegistered
                    ) { toggleClaudeHooks() }
                } else {
                    HStack {
                        Image(systemName: "terminal.fill")
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Claude Code")
                            Text("Not detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                if let agentMessage {
                    Text(agentMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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
                        .help("Remove Editor")
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

        }
        .formStyle(.grouped)
        .labelsHidden()
        .frame(width: 450)
        .navigationTitle("Settings")
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
    private func agentSubRow(
        name: String,
        enabled: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if enabled {
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
            Button(enabled ? "Disable" : "Enable") {
                onToggle()
            }
        }
        .padding(.leading, 34)
    }

    private func toggleAllClaude() {
        if claudeIntegrationService.allEnabled {
            claudeIntegrationService.disableAll()
            agentMessage = nil
        } else {
            do {
                try claudeIntegrationService.enableAll()
                agentMessage = "Restart Claude Code to activate"
            } catch {
                agentMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func toggleClaudeCode() {
        if claudeIntegrationService.mcpRegistered {
            claudeIntegrationService.disableMCP()
            agentMessage = nil
        } else {
            do {
                try claudeIntegrationService.enableMCP()
                agentMessage = "Restart Claude Code to activate"
            } catch {
                agentMessage = "Failed to register MCP: \(error.localizedDescription)"
            }
        }
    }

    private func toggleClaudeHooks() {
        if claudeIntegrationService.hooksRegistered {
            claudeIntegrationService.disableHooks()
            agentMessage = nil
        } else {
            do {
                try claudeIntegrationService.enableHooks()
                if claudeIntegrationService.hooksRegistered {
                    agentMessage = "Restart Claude Code to activate"
                } else {
                    agentMessage = "Failed to verify hooks in settings file"
                }
            } catch {
                agentMessage = "Failed to write hooks: \(error.localizedDescription)"
            }
        }
    }
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
