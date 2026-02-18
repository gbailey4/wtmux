import AppKit
import SwiftUI
import WTCore
import WTTerminal
import WTTransport
import os.log

private let logger = Logger(subsystem: "com.wtmux", category: "ProjectSettingsView")

struct ProjectSettingsView: View {
    @Bindable var project: Project
    let terminalSessionManager: TerminalSessionManager
    let paneManager: SplitPaneManager
    @Environment(\.dismiss) private var dismiss
    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService

    @State private var name: String
    @State private var repoPath: String
    @State private var defaultBranch: String
    @State private var worktreeBasePath: String
    @State private var isRemote: Bool
    @State private var sshHost: String
    @State private var sshUser: String
    @State private var sshPort: String

    // Appearance
    @State private var selectedColor: String
    @State private var selectedIcon: String

    // Profile fields
    @State private var runConfigurations: [EditableRunConfig]
    @State private var setupCommands: [String]
    @State private var filesToCopy: [String]
    @State private var terminalStartCommand: String
    @State private var startClaudeInTerminals: Bool
    @State private var confirmSetupRerun: Bool

    init(project: Project, terminalSessionManager: TerminalSessionManager, paneManager: SplitPaneManager) {
        self.project = project
        self.terminalSessionManager = terminalSessionManager
        self.paneManager = paneManager
        _name = State(initialValue: project.name)
        _repoPath = State(initialValue: project.repoPath)
        _defaultBranch = State(initialValue: project.defaultBranch)
        _worktreeBasePath = State(initialValue: project.worktreeBasePath)
        _isRemote = State(initialValue: project.isRemote)
        _sshHost = State(initialValue: project.sshHost ?? "")
        _sshUser = State(initialValue: project.sshUser ?? "")
        _sshPort = State(initialValue: project.sshPort.map(String.init) ?? "22")

        // Appearance
        _selectedColor = State(initialValue: project.colorName ?? Project.colorPalette[0])
        _selectedIcon = State(initialValue: project.resolvedIconName)

        // Initialize profile fields
        let profile = project.profile
        _setupCommands = State(initialValue: profile?.setupCommands ?? [])
        _filesToCopy = State(initialValue: profile?.filesToCopy ?? [])
        _terminalStartCommand = State(initialValue: profile?.terminalStartCommand ?? "")
        _startClaudeInTerminals = State(initialValue: profile?.terminalStartCommand == "claude")
        _confirmSetupRerun = State(initialValue: profile?.confirmSetupRerun ?? true)
        _runConfigurations = State(initialValue: (profile?.runConfigurations ?? [])
            .sorted { $0.order < $1.order }
            .map { EditableRunConfig(
                name: $0.name,
                command: $0.command,
                portString: $0.port.map(String.init) ?? "",
                autoStart: $0.autoStart
            )}
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        configureWithClaudeButton
                        Spacer()
                        reloadFromFileButton
                    }
                }

                Section("Appearance") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(Project.colorPalette, id: \.self) { name in
                                let color = Color.fromPaletteName(name) ?? .gray
                                Circle()
                                    .fill(color)
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        if name == selectedColor {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture { selectedColor = name }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 8) {
                            ForEach(Project.iconPalette, id: \.self) { icon in
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(icon == selectedIcon ? Color.accentColor.opacity(0.2) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(icon == selectedIcon ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                                    .onTapGesture { selectedIcon = icon }
                            }
                        }
                    }
                }

                Section("Repository") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Name")
                            .foregroundStyle(.secondary)
                        TextField("", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Repository Path")
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("", text: $repoPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                browseRepoPath()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default Branch")
                            .foregroundStyle(.secondary)
                        TextField("", text: $defaultBranch)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Worktree Base Path")
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("", text: $worktreeBasePath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                browseWorktreeBasePath()
                            }
                        }
                    }
                    .help("Directory where worktrees will be created")
                }

                Section("Connection") {
                    HStack {
                        Text("Remote (SSH)")
                        Spacer()
                        Toggle("", isOn: $isRemote)
                    }

                    if isRemote {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SSH Host")
                                .foregroundStyle(.secondary)
                            TextField("", text: $sshHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SSH User")
                                .foregroundStyle(.secondary)
                            TextField("", text: $sshUser)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SSH Port")
                                .foregroundStyle(.secondary)
                            TextField("", text: $sshPort)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                Section("Files to Copy") {
                    ForEach(Array(filesToCopy.enumerated()), id: \.offset) { index, _ in
                        HStack {
                            TextField("Pattern (e.g. .env*, .claude/)", text: $filesToCopy[index])
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button(role: .destructive) {
                                filesToCopy.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                    }
                    Button {
                        filesToCopy.append("")
                    } label: {
                        Label("Add Pattern", systemImage: "plus")
                    }
                }

                Section("Setup Commands") {
                    ForEach(Array(setupCommands.enumerated()), id: \.offset) { index, _ in
                        HStack {
                            TextField("Command", text: $setupCommands[index])
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button(role: .destructive) {
                                setupCommands.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                    }
                    Button {
                        setupCommands.append("")
                    } label: {
                        Label("Add Command", systemImage: "plus")
                    }
                    Toggle("Confirm before re-running setup", isOn: $confirmSetupRerun)
                }

                Section("Terminal") {
                    Toggle("Start Claude in new terminals", isOn: $startClaudeInTerminals)
                    if !startClaudeInTerminals {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start Command")
                                .foregroundStyle(.secondary)
                            TextField("", text: $terminalStartCommand)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Text("Runs automatically in every new terminal tab")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Run Configurations") {
                    ForEach(Array(runConfigurations.enumerated()), id: \.offset) { index, _ in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Name")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("", text: $runConfigurations[index].name)
                                        .textFieldStyle(.roundedBorder)
                                }
                                Button(role: .destructive) {
                                    runConfigurations.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Remove")
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Command")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("", text: $runConfigurations[index].command)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Port")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("", text: $runConfigurations[index].portString)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                }
                                HStack {
                                    Toggle("", isOn: $runConfigurations[index].autoStart)
                                    Text("Default runner")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        runConfigurations.append(EditableRunConfig())
                    } label: {
                        Label("Add Configuration", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)
            .labelsHidden()
            .padding()

            Divider()

            VStack(spacing: 8) {
                Text(".wtmux will be added to .gitignore if not already present.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || repoPath.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 550, height: 600)
    }

    private func browseRepoPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the git repository root"
        if !repoPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: repoPath).deletingLastPathComponent()
        }

        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
        }
    }

    private func browseWorktreeBasePath() {
        if let path = FileBrowseHelper.browseForDirectory(
            message: "Select worktree base directory",
            startingIn: repoPath
        ) {
            worktreeBasePath = path
        }
    }

    @ViewBuilder
    private var configureWithClaudeButton: some View {
        if project.worktrees.isEmpty {
            Label("Configure with Claude", systemImage: "terminal")
                .foregroundStyle(.secondary)
                .help("Add a worktree first to configure with Claude")
        } else {
            Button {
                let worktree = project.worktrees.sorted(by: { $0.sortOrder < $1.sortOrder }).first!
                dismiss()
                // Defer so the column is available after sheet dismissal
                DispatchQueue.main.async {
                    if let loc = paneManager.findWorktreeLocation(worktree.path) {
                        ClaudeConfigHelper.openConfigTerminal(
                            terminalSessionManager: terminalSessionManager,
                            columnId: loc.columnID.uuidString,
                            worktreeId: worktree.path,
                            workingDirectory: worktree.path,
                            repoPath: repoPath
                        )
                    }
                }
            } label: {
                Label("Configure with Claude", systemImage: "terminal")
            }
            .disabled(!claudeIntegrationService.canUseClaudeConfig)
        }
    }

    @ViewBuilder
    private var reloadFromFileButton: some View {
        Button {
            Task {
                let configService = ConfigService()
                if let config = await configService.readConfig(forRepo: repoPath) {
                    filesToCopy = config.filesToCopy
                    setupCommands = config.setupCommands
                    if config.terminalStartCommand == "claude" {
                        startClaudeInTerminals = true
                        terminalStartCommand = ""
                    } else {
                        startClaudeInTerminals = false
                        terminalStartCommand = config.terminalStartCommand ?? ""
                    }
                    runConfigurations = config.runConfigurations.map { rc in
                        EditableRunConfig(
                            name: rc.name,
                            command: rc.command,
                            portString: rc.port.map(String.init) ?? "",
                            autoStart: rc.autoStart
                        )
                    }
                }
            }
        } label: {
            Label("Reload from File", systemImage: "arrow.clockwise")
        }
    }

    private func save() {
        project.name = name
        project.repoPath = repoPath
        project.defaultBranch = defaultBranch
        project.worktreeBasePath = worktreeBasePath
        project.colorName = selectedColor
        project.iconName = selectedIcon
        project.needsClaudeConfig = false

        if isRemote {
            project.sshHost = sshHost.isEmpty ? nil : sshHost
            project.sshUser = sshUser.isEmpty ? nil : sshUser
            project.sshPort = Int(sshPort) ?? 22
        } else {
            project.sshHost = nil
            project.sshUser = nil
            project.sshPort = nil
        }

        // Ensure profile exists
        let profile = project.profile ?? {
            let p = ProjectProfile()
            p.project = project
            project.profile = p
            return p
        }()

        profile.filesToCopy = filesToCopy.filter { !$0.isEmpty }
        profile.setupCommands = setupCommands.filter { !$0.isEmpty }
        profile.confirmSetupRerun = confirmSetupRerun
        profile.terminalStartCommand = startClaudeInTerminals ? "claude" : (terminalStartCommand.isEmpty ? nil : terminalStartCommand)

        // Remove old run configurations
        for existing in profile.runConfigurations {
            profile.runConfigurations.removeAll { $0.name == existing.name }
        }
        profile.runConfigurations.removeAll()

        // Insert updated configurations
        for (index, config) in runConfigurations.enumerated() where !config.name.isEmpty {
            let rc = RunConfiguration(
                name: config.name,
                command: config.command,
                port: Int(config.portString),
                autoStart: config.autoStart,
                order: index
            )
            rc.profile = profile
            profile.runConfigurations.append(rc)
        }

        // Write .wtmux/config.json
        Task {
            let configService = ConfigService()
            let startCmd: String? = startClaudeInTerminals ? "claude" : (terminalStartCommand.isEmpty ? nil : terminalStartCommand)
            let config = ProjectConfig(
                filesToCopy: filesToCopy.filter { !$0.isEmpty },
                setupCommands: setupCommands.filter { !$0.isEmpty },
                runConfigurations: runConfigurations
                    .enumerated()
                    .filter { !$0.element.name.isEmpty }
                    .map { index, rc in
                        ProjectConfig.RunConfig(
                            name: rc.name,
                            command: rc.command,
                            port: Int(rc.portString),
                            autoStart: rc.autoStart,
                            order: index
                        )
                    },
                terminalStartCommand: startCmd
            )
            do {
                try await configService.writeConfig(config, forRepo: repoPath)
                try await configService.ensureGitignore(forRepo: repoPath)
            } catch {
                logger.error("Failed to write config for '\(repoPath)': \(error.localizedDescription)")
            }
        }
    }
}
