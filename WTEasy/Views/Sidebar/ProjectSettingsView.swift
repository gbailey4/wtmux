import SwiftUI
import WTCore

struct ProjectSettingsView: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var repoPath: String
    @State private var defaultBranch: String
    @State private var worktreeBasePath: String
    @State private var isRemote: Bool
    @State private var sshHost: String
    @State private var sshUser: String
    @State private var sshPort: String

    // Profile fields
    @State private var runConfigurations: [EditableRunConfig]
    @State private var setupCommands: [String]
    @State private var envFilesToCopy: [String]
    @State private var terminalStartCommand: String

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _repoPath = State(initialValue: project.repoPath)
        _defaultBranch = State(initialValue: project.defaultBranch)
        _worktreeBasePath = State(initialValue: project.worktreeBasePath)
        _isRemote = State(initialValue: project.isRemote)
        _sshHost = State(initialValue: project.sshHost ?? "")
        _sshUser = State(initialValue: project.sshUser ?? "")
        _sshPort = State(initialValue: project.sshPort.map(String.init) ?? "22")

        // Initialize profile fields
        let profile = project.profile
        _setupCommands = State(initialValue: profile?.setupCommands ?? [])
        _envFilesToCopy = State(initialValue: profile?.envFilesToCopy ?? [])
        _terminalStartCommand = State(initialValue: profile?.terminalStartCommand ?? "")
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

                Section("Environment Files") {
                    ForEach(Array(envFilesToCopy.enumerated()), id: \.offset) { index, _ in
                        HStack {
                            TextField("File path", text: $envFilesToCopy[index])
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button(role: .destructive) {
                                envFilesToCopy.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        browseForEnvFiles()
                    } label: {
                        Label("Add File", systemImage: "plus")
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
                        }
                    }
                    Button {
                        setupCommands.append("")
                    } label: {
                        Label("Add Command", systemImage: "plus")
                    }
                }

                Section("Terminal") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start Command")
                            .foregroundStyle(.secondary)
                        TextField("", text: $terminalStartCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Text("Runs automatically in every new terminal tab (e.g. `claude`)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                                    Text("Auto-start")
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
            .padding()
        }
        .frame(width: 550, height: 600)
        .task {
            // Load from .wteasy/config.json if available (source of truth over SwiftData)
            let configService = ConfigService()
            if let config = await configService.readConfig(forRepo: project.repoPath) {
                envFilesToCopy = config.envFilesToCopy
                setupCommands = config.setupCommands
                terminalStartCommand = config.terminalStartCommand ?? ""
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Select worktree base directory"
        if !repoPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: repoPath).deletingLastPathComponent()
        }

        if panel.runModal() == .OK, let url = panel.url {
            worktreeBasePath = url.path
        }
    }

    private func browseForEnvFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Select environment files to copy to new worktrees"
        panel.directoryURL = URL(fileURLWithPath: repoPath)

        if panel.runModal() == .OK {
            let repoURL = URL(fileURLWithPath: repoPath)
            for url in panel.urls {
                // Store as relative path from repo root when possible
                if let relative = url.path.hasPrefix(repoURL.path)
                    ? String(url.path.dropFirst(repoURL.path.count + 1))
                    : nil, !relative.isEmpty {
                    if !envFilesToCopy.contains(relative) {
                        envFilesToCopy.append(relative)
                    }
                } else {
                    let name = url.lastPathComponent
                    if !envFilesToCopy.contains(name) {
                        envFilesToCopy.append(name)
                    }
                }
            }
        }
    }

    private func save() {
        project.name = name
        project.repoPath = repoPath
        project.defaultBranch = defaultBranch
        project.worktreeBasePath = worktreeBasePath

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

        profile.envFilesToCopy = envFilesToCopy.filter { !$0.isEmpty }
        profile.setupCommands = setupCommands.filter { !$0.isEmpty }
        profile.terminalStartCommand = terminalStartCommand.isEmpty ? nil : terminalStartCommand

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

        // Write .wteasy/config.json
        Task {
            let configService = ConfigService()
            let startCmd = terminalStartCommand.isEmpty ? nil : terminalStartCommand
            let config = ProjectConfig(
                envFilesToCopy: envFilesToCopy.filter { !$0.isEmpty },
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
            try? await configService.writeConfig(config, forRepo: repoPath)
            try? await configService.ensureGitignore(forRepo: repoPath)
        }
    }
}
