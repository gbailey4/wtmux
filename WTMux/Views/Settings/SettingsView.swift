import SwiftUI
import UniformTypeIdentifiers
import WTTerminal

struct SettingsView: View {
    @AppStorage("defaultShell") private var defaultShell = Shell.default
    @AppStorage("terminalFontSize") private var terminalFontSize = 13.0
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @AppStorage("terminalScrollbackLines") private var terminalScrollbackLines = 5000
    @AppStorage("promptForPaneLabel") private var promptForPaneLabel = true

    @State private var customEditors = ExternalEditor.customEditors
    @State private var hiddenEditorIds = ExternalEditor.hiddenEditorIds

    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @Environment(ThemeManager.self) private var themeManager
    @State private var agentMessage: String?
    @State private var importError: String?

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
                    Text("Scrollback")
                    TextField("", value: $terminalScrollbackLines, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("lines")
                        .foregroundStyle(.secondary)
                    Stepper("", value: $terminalScrollbackLines, in: 500...50_000, step: 500)
                        .labelsHidden()
                }
            }

            Section("Panes") {
                Toggle("Prompt for label when creating new panes", isOn: $promptForPaneLabel)
            }

            Section("Theme") {
                themeGrid(themes: TerminalThemes.builtInThemes)

                if !themeManager.customThemes.isEmpty {
                    Divider()
                    Text("Imported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    themeGrid(themes: themeManager.customThemes, allowDelete: true)
                }

                HStack {
                    Button("Import .itermcolors...") {
                        importITermColors()
                    }
                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.red)
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
        .frame(width: 500)
        .navigationTitle("Settings")
    }

    private static let gridColumns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)]

    @ViewBuilder
    private func themeGrid(themes: [TerminalTheme], allowDelete: Bool = false) -> some View {
        LazyVGrid(columns: Self.gridColumns, spacing: 8) {
            ForEach(themes) { theme in
                ThemeCardView(
                    theme: theme,
                    isSelected: terminalThemeId == theme.id,
                    allowDelete: allowDelete
                ) {
                    terminalThemeId = theme.id
                } onDelete: {
                    if terminalThemeId == theme.id {
                        terminalThemeId = TerminalThemes.defaultTheme.id
                    }
                    themeManager.deleteCustomTheme(id: theme.id)
                }
            }
        }
    }

    private func importITermColors() {
        importError = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "itermcolors") ?? .propertyList]
        panel.allowsMultipleSelection = true
        panel.message = "Select .itermcolors theme files"

        guard panel.runModal() == .OK else { return }

        var lastImported: TerminalTheme?
        for url in panel.urls {
            do {
                let theme = try themeManager.importITermColors(from: url)
                lastImported = theme
            } catch {
                importError = "Failed to import \(url.lastPathComponent): \(error)"
            }
        }
        if let lastImported {
            terminalThemeId = lastImported.id
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

private struct ThemeCardView: View {
    let theme: TerminalTheme
    let isSelected: Bool
    var allowDelete: Bool = false
    var onSelect: () -> Void
    var onDelete: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // Terminal preview
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.background.toColor())
                        .frame(height: 52)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("~/project")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(theme.foreground.toColor())
                        HStack(spacing: 2) {
                            ForEach(0..<8) { i in
                                Circle()
                                    .fill(theme.ansiColors[i].toColor())
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .padding(5)

                    if allowDelete && isHovered {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white, .red)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                    }
                }

                Text(theme.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onHover { isHovered = $0 }
    }
}
