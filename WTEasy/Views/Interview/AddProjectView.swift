import SwiftUI
import SwiftData
import WTCore
import WTGit
import WTTransport

struct AddProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var step: InterviewStep = .selectRepo
    @State private var repoPath = ""
    @State private var projectName = ""
    @State private var defaultBranch = "main"
    @State private var worktreeBasePath = ""
    @State private var isRemote = false
    @State private var sshHost = ""
    @State private var sshUser = ""
    @State private var sshPort = "22"

    // Profile
    @State private var detectedEnvFiles: [String] = []
    @State private var selectedEnvFiles: Set<String> = []
    @State private var detectedScripts: [DetectedScript] = []
    @State private var setupCommands: [String] = []
    @State private var terminalStartCommand = ""
    @State private var runConfigurations: [EditableRunConfig] = []

    @State private var errorMessage: String?
    @State private var isLoading = false

    enum InterviewStep: CaseIterable {
        case selectRepo
        case configureProfile
        case review
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack {
                ForEach(Array(InterviewStep.allCases.enumerated()), id: \.offset) { index, s in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(s == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text(stepTitle(s))
                            .font(.caption)
                            .foregroundStyle(s == step ? .primary : .secondary)
                    }
                    if index < InterviewStep.allCases.count - 1 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)
                            .frame(maxWidth: 40)
                    }
                }
            }
            .padding()

            Divider()

            // Step content
            Group {
                switch step {
                case .selectRepo:
                    selectRepoStep
                case .configureProfile:
                    configureProfileStep
                case .review:
                    reviewStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            // Navigation buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if step != .selectRepo {
                    Button("Back") { goBack() }
                }
                Button(step == .review ? "Create Project" : "Next") {
                    if step == .review {
                        createProject()
                    } else {
                        goNext()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }

    @ViewBuilder
    private var selectRepoStep: some View {
        Form {
            Section("Repository") {
                HStack {
                    TextField("Repository Path", text: $repoPath)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                    Button("Browse...") {
                        selectFolder()
                    }
                }

                TextField("Project Name", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)

                TextField("Default Branch", text: $defaultBranch)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)

                HStack {
                    TextField("Worktree Base Path", text: $worktreeBasePath)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                    Button("Browse...") {
                        browseWorktreeBasePath()
                    }
                }
                .help("Directory where worktrees will be created")
            }

            Section("Connection") {
                Toggle("Remote (SSH)", isOn: $isRemote)

                if isRemote {
                    TextField("SSH Host", text: $sshHost)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                    TextField("SSH User", text: $sshUser)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                    TextField("SSH Port", text: $sshPort)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var configureProfileStep: some View {
        Form {
            Section("Environment Files to Copy") {
                ForEach(detectedEnvFiles, id: \.self) { file in
                    Toggle(file, isOn: Binding(
                        get: { selectedEnvFiles.contains(file) },
                        set: { selected in
                            if selected { selectedEnvFiles.insert(file) }
                            else { selectedEnvFiles.remove(file) }
                        }
                    ))
                }
                if detectedEnvFiles.isEmpty {
                    Text("No .env files detected")
                        .foregroundStyle(.secondary)
                }
                Button {
                    browseForEnvFiles()
                } label: {
                    Label("Browse...", systemImage: "folder")
                }
            }

            Section("Setup Commands") {
                ForEach(Array(setupCommands.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField("Command", text: $setupCommands[index])
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
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
                TextField("Start Command", text: $terminalStartCommand)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .font(.system(.body, design: .monospaced))
                Text("Runs automatically in every new terminal tab (e.g. `claude`)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Run Configurations") {
                ForEach(Array(runConfigurations.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: $runConfigurations[index].name)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                            Button(role: .destructive) {
                                runConfigurations.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("Command", text: $runConfigurations[index].command)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .font(.system(.body, design: .monospaced))
                        HStack {
                            TextField("Port", text: $runConfigurations[index].portString)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                                .frame(width: 80)
                            Toggle("Auto-start", isOn: $runConfigurations[index].autoStart)
                        }
                    }
                    .labelsHidden()
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
    }

    @ViewBuilder
    private var reviewStep: some View {
        Form {
            Section("Project") {
                LabeledContent("Name", value: projectName)
                LabeledContent("Path", value: repoPath)
                LabeledContent("Default Branch", value: defaultBranch)
                LabeledContent("Worktrees", value: worktreeBasePath)
            }

            if !selectedEnvFiles.isEmpty {
                Section("Files to Copy") {
                    ForEach(Array(selectedEnvFiles), id: \.self) { file in
                        Text(file)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            if !setupCommands.filter({ !$0.isEmpty }).isEmpty {
                Section("Setup Commands") {
                    ForEach(setupCommands.filter { !$0.isEmpty }, id: \.self) { cmd in
                        Text(cmd)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            if !terminalStartCommand.isEmpty {
                Section("Terminal Start Command") {
                    Text(terminalStartCommand)
                        .font(.system(.body, design: .monospaced))
                }
            }

            if !runConfigurations.filter({ !$0.name.isEmpty }).isEmpty {
                Section("Run Configurations") {
                    ForEach(runConfigurations.filter { !$0.name.isEmpty }, id: \.name) { config in
                        LabeledContent(config.name, value: config.command)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var canAdvance: Bool {
        switch step {
        case .selectRepo:
            return !repoPath.isEmpty && !projectName.isEmpty
        case .configureProfile:
            return true
        case .review:
            return true
        }
    }

    private func goNext() {
        switch step {
        case .selectRepo:
            if worktreeBasePath.isEmpty {
                worktreeBasePath = "\(repoPath)-worktrees"
            }
            Task { await detectProjectConfig() }
            step = .configureProfile
        case .configureProfile:
            step = .review
        case .review:
            break
        }
    }

    private func goBack() {
        switch step {
        case .selectRepo: break
        case .configureProfile: step = .selectRepo
        case .review: step = .configureProfile
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the git repository root"

        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
            if projectName.isEmpty {
                projectName = url.lastPathComponent
            }
        }
    }

    private func detectProjectConfig() async {
        isLoading = true
        defer { isLoading = false }

        let transport = LocalTransport()

        // Detect default branch
        let git = GitService(transport: transport, repoPath: repoPath)
        if let branch = try? await git.defaultBranch() {
            defaultBranch = branch
        }

        // Detect .env files recursively
        detectedEnvFiles = EnvFileScanner.scan(repoPath: repoPath)
        selectedEnvFiles = Set(detectedEnvFiles)

        // Detect package.json scripts
        let packageJsonPath = "\(repoPath)/package.json"
        let catResult = try? await transport.execute(
            ["cat", packageJsonPath],
            in: repoPath
        )
        if let catResult, catResult.succeeded,
           let data = catResult.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: String] {

            // Detect setup command
            if scripts["install"] != nil || FileManager.default.fileExists(atPath: packageJsonPath) {
                if FileManager.default.fileExists(atPath: "\(repoPath)/bun.lockb") {
                    setupCommands = ["bun install"]
                } else if FileManager.default.fileExists(atPath: "\(repoPath)/pnpm-lock.yaml") {
                    setupCommands = ["pnpm install"]
                } else if FileManager.default.fileExists(atPath: "\(repoPath)/yarn.lock") {
                    setupCommands = ["yarn install"]
                } else {
                    setupCommands = ["npm install"]
                }
            }

            // Detect run configurations
            let devScripts = ["dev", "start", "serve"]
            for script in devScripts {
                if let cmd = scripts[script] {
                    runConfigurations.append(EditableRunConfig(
                        name: script.capitalized,
                        command: detectPackageManager() + " run \(script)",
                        portString: extractPort(from: cmd) ?? "",
                        autoStart: script == "dev"
                    ))
                }
            }
        }

        // Detect Python projects
        if FileManager.default.fileExists(atPath: "\(repoPath)/requirements.txt") {
            setupCommands = ["pip install -r requirements.txt"]
        } else if FileManager.default.fileExists(atPath: "\(repoPath)/pyproject.toml") {
            setupCommands = ["pip install -e ."]
        }
    }

    private func detectPackageManager() -> String {
        if FileManager.default.fileExists(atPath: "\(repoPath)/bun.lockb") { return "bun" }
        if FileManager.default.fileExists(atPath: "\(repoPath)/pnpm-lock.yaml") { return "pnpm" }
        if FileManager.default.fileExists(atPath: "\(repoPath)/yarn.lock") { return "yarn" }
        return "npm"
    }

    private func extractPort(from command: String) -> String? {
        // Simple port extraction from common patterns like "--port 3000" or ":3000"
        let patterns = [
            #"--port\s+(\d+)"#,
            #"-p\s+(\d+)"#,
            #":(\d{4,5})"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
               let range = Range(match.range(at: 1), in: command) {
                return String(command[range])
            }
        }
        return nil
    }

    private func createProject() {
        let project = Project(
            name: projectName,
            repoPath: repoPath,
            defaultBranch: defaultBranch,
            worktreeBasePath: worktreeBasePath
        )

        if isRemote {
            project.sshHost = sshHost
            project.sshUser = sshUser
            project.sshPort = Int(sshPort) ?? 22
        }

        // Create profile
        let profile = ProjectProfile()
        profile.envFilesToCopy = Array(selectedEnvFiles)
        profile.setupCommands = setupCommands.filter { !$0.isEmpty }
        profile.terminalStartCommand = terminalStartCommand.isEmpty ? nil : terminalStartCommand

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

        profile.project = project
        project.profile = profile

        modelContext.insert(project)
        try? modelContext.save()

        // Write .wteasy/config.json and update .gitignore
        Task {
            let configService = ConfigService()
            let startCmd = terminalStartCommand.isEmpty ? nil : terminalStartCommand
            let config = ProjectConfig(
                envFilesToCopy: Array(selectedEnvFiles),
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

        dismiss()
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
                if let relative = url.path.hasPrefix(repoURL.path)
                    ? String(url.path.dropFirst(repoURL.path.count + 1))
                    : nil, !relative.isEmpty {
                    if !detectedEnvFiles.contains(relative) {
                        detectedEnvFiles.append(relative)
                    }
                    selectedEnvFiles.insert(relative)
                } else {
                    let name = url.lastPathComponent
                    if !detectedEnvFiles.contains(name) {
                        detectedEnvFiles.append(name)
                    }
                    selectedEnvFiles.insert(name)
                }
            }
        }
    }

    private func stepTitle(_ step: InterviewStep) -> String {
        switch step {
        case .selectRepo: "Repository"
        case .configureProfile: "Configure"
        case .review: "Review"
        }
    }
}

struct DetectedScript {
    let name: String
    let command: String
}
