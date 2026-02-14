import AppKit
import SwiftUI
import SwiftData
import WTCore
import WTGit
import WTLLM
import WTTerminal
import WTTransport
import os.log

private let logger = Logger(subsystem: "com.wteasy", category: "AddProjectView")

struct AddProjectView: View {
    @Binding var selectedWorktreeID: String?
    let terminalSessionManager: TerminalSessionManager

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
    @State private var setupCommands: [String] = []
    @State private var terminalStartCommand = ""
    @State private var startClaudeInTerminals = false
    @State private var runConfigurations: [EditableRunConfig] = []

    // Existing worktrees
    @State private var detectedWorktrees: [GitWorktreeInfo] = []
    @State private var selectedWorktreePaths: Set<String> = []

    @State private var errorMessage: String?
    @State private var isLoading = false

    // AI analysis
    @AppStorage("llmModel") private var llmModel = "claude-sonnet-4-5-20250929"
    @State private var analysisManager = AIAnalysisManager()

    // Configure with Claude
    @State private var showFirstWorktreeAlert = false
    @State private var firstWorktreeBranch = ""

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
        .alert("Create First Worktree", isPresented: $showFirstWorktreeAlert) {
            TextField("Branch name", text: $firstWorktreeBranch)
            Button("Create") {
                createBareProjectWithClaude()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a branch name for your first worktree. Claude will auto-configure the project in the terminal.")
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
            Section {
                Button {
                    firstWorktreeBranch = ""
                    showFirstWorktreeAlert = true
                } label: {
                    HStack {
                        Image(systemName: "terminal")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Configure with Claude")
                                .fontWeight(.medium)
                            Text("Create a worktree and let Claude CLI auto-configure the project")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                aiAnalysisButton
            }

            if !detectedWorktrees.isEmpty {
                Section("Existing Worktrees") {
                    ForEach(detectedWorktrees, id: \.path) { wt in
                        Toggle(isOn: Binding(
                            get: { selectedWorktreePaths.contains(wt.path) },
                            set: { selected in
                                if selected { selectedWorktreePaths.insert(wt.path) }
                                else { selectedWorktreePaths.remove(wt.path) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent)
                                    .font(.body)
                                Text(wt.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

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
                Toggle("Start Claude in new terminals", isOn: $startClaudeInTerminals)
                if !startClaudeInTerminals {
                    TextField("Start Command", text: $terminalStartCommand)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .font(.system(.body, design: .monospaced))
                    Text("Runs automatically in every new terminal tab")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                            Toggle("Default runner", isOn: $runConfigurations[index].autoStart)
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
        .sheet(isPresented: $analysisManager.showAnalysisPreview) {
            if let analysis = analysisManager.pendingAnalysis {
                AIAnalysisPreviewSheet(analysis: analysis) {
                    applyAnalysis(analysis)
                    analysisManager.dismissPreview()
                } onCancel: {
                    analysisManager.dismissPreview()
                }
            }
        }
    }

    @ViewBuilder
    private var aiAnalysisButton: some View {
        if let apiKey = KeychainStore.loadAPIKey(for: .claude) {
            switch analysisManager.state {
            case .idle, .failed:
                Button {
                    analysisManager.runAnalysis(apiKey: apiKey, model: llmModel, repoPath: repoPath)
                } label: {
                    Label("Auto-detect with AI", systemImage: "sparkles")
                }
                if case .failed(let message) = analysisManager.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        analysisManager.runAnalysis(apiKey: apiKey, model: llmModel, repoPath: repoPath)
                    }
                    .font(.caption)
                }
            case .gatheringContext:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Gathering project files...")
                        .foregroundStyle(.secondary)
                }
            case .analyzing:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing project...")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("Configure an AI provider in Settings to auto-detect project configuration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingsLink {
                    Text("Open Settings")
                        .font(.caption)
                }
            }
        }
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

            if !selectedWorktreePaths.isEmpty {
                Section("Worktrees to Import") {
                    ForEach(detectedWorktrees.filter({ selectedWorktreePaths.contains($0.path) }), id: \.path) { wt in
                        LabeledContent(
                            wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent,
                            value: wt.path
                        )
                    }
                }
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

            if startClaudeInTerminals || !terminalStartCommand.isEmpty {
                Section("Terminal Start Command") {
                    Text(startClaudeInTerminals ? "claude" : terminalStartCommand)
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

        // Detect existing worktrees
        if let worktrees = try? await git.worktreeList() {
            let filtered = worktrees.filter { !$0.isBare && $0.path != repoPath }
            detectedWorktrees = filtered
            selectedWorktreePaths = Set(filtered.map(\.path))
        }

        // Detect .env files recursively
        detectedEnvFiles = EnvFileScanner.scan(repoPath: repoPath)
        selectedEnvFiles = Set(detectedEnvFiles)

        // Detect package.json scripts
        let packageJsonURL = URL(fileURLWithPath: "\(repoPath)/package.json")
        if let data = try? Data(contentsOf: packageJsonURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: String] {

            // Detect setup command
            if scripts["install"] != nil || FileManager.default.fileExists(atPath: packageJsonURL.path) {
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

    private func applyAnalysis(_ analysis: ProjectAnalysis) {
        detectedEnvFiles = analysis.envFilesToCopy
        selectedEnvFiles = Set(analysis.envFilesToCopy)
        setupCommands = analysis.setupCommands
        if analysis.terminalStartCommand == "claude" {
            startClaudeInTerminals = true
            terminalStartCommand = ""
        } else {
            terminalStartCommand = analysis.terminalStartCommand ?? ""
        }
        runConfigurations = analysis.toEditableRunConfigs()
    }

    /// Returns an existing project that already uses this `repoPath`, or `nil`.
    private func existingProject(for path: String) -> Project? {
        let predicate = #Predicate<Project> { $0.repoPath == path }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    private func createBareProjectWithClaude() {
        let branchName = firstWorktreeBranch.trimmingCharacters(in: .whitespaces)
        guard !branchName.isEmpty else { return }

        errorMessage = nil

        Task {
            // 1. Create git worktree
            let transport = LocalTransport()
            let git = GitService(transport: transport, repoPath: repoPath)
            let worktreePath = "\(worktreeBasePath)/\(branchName)"

            do {
                try await git.worktreeAdd(
                    path: worktreePath,
                    branch: branchName,
                    baseBranch: defaultBranch
                )
            } catch {
                errorMessage = "Failed to create worktree: \(error.localizedDescription)"
                return
            }

            // 2. Create or reuse project
            let project: Project
            if let existing = existingProject(for: repoPath) {
                project = existing
                // Update fields but preserve user-chosen name
                project.defaultBranch = defaultBranch
                project.worktreeBasePath = worktreeBasePath
            } else {
                project = Project(
                    name: projectName,
                    repoPath: repoPath,
                    defaultBranch: defaultBranch,
                    worktreeBasePath: worktreeBasePath
                )
                modelContext.insert(project)
            }
            if isRemote {
                project.sshHost = sshHost
                project.sshUser = sshUser
                project.sshPort = Int(sshPort) ?? 22
            }

            // Ensure profile exists
            if project.profile == nil {
                let profile = ProjectProfile()
                profile.project = project
                project.profile = profile
            }

            // 3. Create worktree model
            let worktree = Worktree(
                branchName: branchName,
                path: worktreePath,
                baseBranch: defaultBranch,
                status: .ready
            )
            worktree.project = project

            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save project with Claude setup: \(error.localizedDescription)")
            }

            // 4. Pre-create terminal session with claude command
            let claudeCommand = #"claude "Analyze this repo and use the wteasy MCP configure_project tool to configure it. Determine appropriate setup commands, run configurations (dev servers with ports), env files to copy between worktrees, and terminal start command.""#
            _ = terminalSessionManager.createTab(
                forWorktree: worktreePath,
                workingDirectory: worktreePath,
                initialCommand: claudeCommand
            )

            // 5. Navigate to the new worktree and dismiss
            selectedWorktreeID = worktreePath
            dismiss()
        }
    }

    private func createProject() {
        // Reuse an existing project for this repo path if one already exists
        let project: Project
        if let existing = existingProject(for: repoPath) {
            project = existing
            project.defaultBranch = defaultBranch
            project.worktreeBasePath = worktreeBasePath
        } else {
            project = Project(
                name: projectName,
                repoPath: repoPath,
                defaultBranch: defaultBranch,
                worktreeBasePath: worktreeBasePath
            )
            modelContext.insert(project)
        }

        if isRemote {
            project.sshHost = sshHost
            project.sshUser = sshUser
            project.sshPort = Int(sshPort) ?? 22
        }

        // Create or update profile
        let profile = project.profile ?? ProjectProfile()
        profile.envFilesToCopy = Array(selectedEnvFiles)
        profile.setupCommands = setupCommands.filter { !$0.isEmpty }
        profile.terminalStartCommand = startClaudeInTerminals ? "claude" : (terminalStartCommand.isEmpty ? nil : terminalStartCommand)

        // Clear existing run configurations before adding new ones
        for rc in profile.runConfigurations {
            modelContext.delete(rc)
        }
        profile.runConfigurations = []

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

        // Import selected existing worktrees
        let existingPaths = Set(project.worktrees.map(\.path))
        for wt in detectedWorktrees where selectedWorktreePaths.contains(wt.path) {
            guard !existingPaths.contains(wt.path) else { continue }
            let branchName = wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent
            let worktree = Worktree(
                branchName: branchName,
                path: wt.path,
                baseBranch: defaultBranch,
                status: .ready
            )
            worktree.project = project
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save new project '\(projectName)': \(error.localizedDescription)")
        }

        // Write .wteasy/config.json and update .gitignore
        Task {
            let configService = ConfigService()
            let startCmd: String? = startClaudeInTerminals ? "claude" : (terminalStartCommand.isEmpty ? nil : terminalStartCommand)
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
            do {
                try await configService.writeConfig(config, forRepo: repoPath)
                try await configService.ensureGitignore(forRepo: repoPath)
            } catch {
                logger.error("Failed to write config for '\(repoPath)': \(error.localizedDescription)")
            }
        }

        dismiss()
    }

    private func browseWorktreeBasePath() {
        if let path = FileBrowseHelper.browseForDirectory(
            message: "Select worktree base directory",
            startingIn: repoPath
        ) {
            worktreeBasePath = path
        }
    }

    private func browseForEnvFiles() {
        let (detected, selected) = FileBrowseHelper.browseForEnvFiles(
            repoPath: repoPath,
            existing: detectedEnvFiles
        )
        detectedEnvFiles = detected
        for file in selected {
            selectedEnvFiles.insert(file)
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

struct AIAnalysisPreviewSheet: View {
    let analysis: ProjectAnalysis
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("AI Analysis Results")
                .font(.headline)
                .padding()

            if let projectType = analysis.projectType {
                Text("Detected: \(projectType)")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            Divider()

            Form {
                if !analysis.envFilesToCopy.isEmpty {
                    Section("Environment Files") {
                        ForEach(analysis.envFilesToCopy, id: \.self) { file in
                            Text(file)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                if !analysis.setupCommands.isEmpty {
                    Section("Setup Commands") {
                        ForEach(analysis.setupCommands, id: \.self) { cmd in
                            Text(cmd)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                if let startCmd = analysis.terminalStartCommand {
                    Section("Terminal Start Command") {
                        Text(startCmd)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                if !analysis.runConfigurations.isEmpty {
                    Section("Run Configurations") {
                        ForEach(analysis.runConfigurations) { rc in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rc.name)
                                    .font(.headline)
                                Text(rc.command)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                HStack {
                                    if let port = rc.port {
                                        Text("Port: \(port)")
                                            .font(.caption)
                                    }
                                    if rc.autoStart {
                                        Text("Default")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }

                if let notes = analysis.notes {
                    Section("Notes") {
                        Text(notes)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply", action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }
}
