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
                    TextField("Project Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Repository Path", text: $repoPath)
                        .textFieldStyle(.roundedBorder)

                    TextField("Default Branch", text: $defaultBranch)
                        .textFieldStyle(.roundedBorder)

                    TextField("Worktree Base Path", text: $worktreeBasePath)
                        .textFieldStyle(.roundedBorder)
                        .help("Directory where worktrees will be created")
                }

                Section("Connection") {
                    Toggle("Remote (SSH)", isOn: $isRemote)

                    if isRemote {
                        TextField("SSH Host", text: $sshHost)
                            .textFieldStyle(.roundedBorder)
                        TextField("SSH User", text: $sshUser)
                            .textFieldStyle(.roundedBorder)
                        TextField("SSH Port", text: $sshPort)
                            .textFieldStyle(.roundedBorder)
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

                Section("Run Configurations") {
                    ForEach(Array(runConfigurations.enumerated()), id: \.offset) { index, _ in
                        VStack(alignment: .leading) {
                            HStack {
                                TextField("Name", text: $runConfigurations[index].name)
                                    .textFieldStyle(.roundedBorder)
                                Button(role: .destructive) {
                                    runConfigurations.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                            TextField("Command", text: $runConfigurations[index].command)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            HStack {
                                TextField("Port", text: $runConfigurations[index].portString)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Toggle("Auto-start", isOn: $runConfigurations[index].autoStart)
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
    }
}
