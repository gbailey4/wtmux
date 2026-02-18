import AppKit
import SwiftUI
import SwiftData
import WTCore
import WTGit
import WTTransport
import os.log

private let logger = Logger(subsystem: "com.wtmux", category: "AddProjectView")

struct AddProjectView: View {
    @Binding var selectedWorktreeID: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService

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
    @State private var filePatterns: [String] = []
    @State private var activePresets: Set<FilePreset> = []
    @State private var setupCommands: [String] = []
    @State private var terminalStartCommand = ""
    @State private var startClaudeInTerminals = false
    @State private var customPatternInput = ""
    @State private var runConfigurations: [EditableRunConfig] = []

    // Existing worktrees
    @State private var detectedWorktrees: [GitWorktreeInfo] = []
    @State private var selectedWorktreePaths: Set<String> = []

    @State private var availableBranches: [String] = []
    @State private var repoError: String?

    @State private var errorMessage: String?
    @State private var isLoading = false

    // Configure with Claude
    @State private var showFirstWorktreeAlert = false
    @State private var firstWorktreeBranch = ""
    @State private var claudeEnableError: String?

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
                if step == .selectRepo {
                    Button("Manual Setup") {
                        goNext()
                    }
                    .disabled(!canAdvance)
                    if claudeIntegrationService.claudeCodeInstalled {
                        VStack(alignment: .trailing, spacing: 4) {
                            Button("Configure with Claude") {
                                if worktreeBasePath.isEmpty {
                                    worktreeBasePath = "\(repoPath)-worktrees"
                                }
                                firstWorktreeBranch = ""
                                showFirstWorktreeAlert = true
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canAdvance || !claudeIntegrationService.canUseClaudeConfig)
                            if !claudeIntegrationService.mcpRegistered {
                                HStack(spacing: 4) {
                                    Text("Claude Code integration not enabled.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("Enable") {
                                        enableClaudeIntegration()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.link)
                                }
                            }
                            if let claudeEnableError {
                                Text(claudeEnableError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } else {
                    Button("Back") { goBack() }
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
            }
            .padding()
        }
        .sheet(isPresented: $showFirstWorktreeAlert) {
            FirstWorktreeSheet(
                availableBranches: availableBranches,
                onCancel: { showFirstWorktreeAlert = false },
                onCreate: { branch, isExisting in
                    firstWorktreeBranch = branch
                    showFirstWorktreeAlert = false
                    createBareProjectWithClaude(isExistingBranch: isExisting)
                }
            )
        }
        .frame(width: 600, height: 500)
    }

    @ViewBuilder
    private var selectRepoStep: some View {
        Form {
            Section("Repository") {
                HStack {
                    TextField("Repository Path", text: $repoPath)
                    Button("Browse...") {
                        selectFolder()
                    }
                    .fixedSize()
                }

                if let repoError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(repoError)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Initialize Repository") {
                            initializeRepo()
                        }
                    }
                    .font(.caption)
                }

                TextField("Project Name", text: $projectName)

                Picker("Default Branch", selection: $defaultBranch) {
                    if availableBranches.isEmpty {
                        Text("Select a repository first").tag("main")
                    }
                    ForEach(availableBranches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .disabled(availableBranches.isEmpty)

                HStack {
                    TextField("Worktree Base Path", text: $worktreeBasePath)
                    Button("Browse...") {
                        browseWorktreeBasePath()
                    }
                    .fixedSize()
                }
                .disabled(availableBranches.isEmpty)
                .help("Directory where worktrees will be created")
                Text("Defaults to a sibling directory (e.g. repo-worktrees/). Should be outside the repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Connection") {
                Toggle("Remote (SSH)", isOn: $isRemote)

                if isRemote {
                    TextField("SSH Host", text: $sshHost)
                    TextField("SSH User", text: $sshUser)
                    TextField("SSH Port", text: $sshPort)
                }
            }

        }
        .formStyle(.grouped)
        .padding()
        .task(id: repoPath) {
            await loadBranches()
        }
    }

    @ViewBuilder
    private var configureProfileStep: some View {
        Form {
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

            Section("Files to Copy") {
                ForEach(FilePreset.allCases) { preset in
                    Toggle(isOn: Binding(
                        get: { activePresets.contains(preset) },
                        set: { enabled in
                            if enabled {
                                activePresets.insert(preset)
                                if !filePatterns.contains(preset.pattern) {
                                    filePatterns.append(preset.pattern)
                                }
                            } else {
                                activePresets.remove(preset)
                                filePatterns.removeAll { $0 == preset.pattern }
                            }
                        }
                    )) {
                        HStack {
                            Text(preset.displayName)
                            Text(preset.pattern)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(customPatterns, id: \.self) { pattern in
                    HStack {
                        Text(pattern)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            filePatterns.removeAll { $0 == pattern }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Custom pattern (e.g. config/*.json)", text: $customPatternInput)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addCustomPattern() }
                    Button("Add") { addCustomPattern() }
                        .disabled(customPatternInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Setup Commands") {
                ForEach(Array(setupCommands.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField("Command", text: $setupCommands[index])
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
                            Button(role: .destructive) {
                                runConfigurations.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("Command", text: $runConfigurations[index].command)
                            .font(.system(.body, design: .monospaced))
                        HStack {
                            TextField("Port", text: $runConfigurations[index].portString)
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

            if !filePatterns.isEmpty {
                Section("Files to Copy") {
                    ForEach(filePatterns, id: \.self) { pattern in
                        Text(pattern)
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

            Section {
                Text(".wtmux will be added to .gitignore if not already present.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var canAdvance: Bool {
        switch step {
        case .selectRepo:
            return !repoPath.isEmpty && !projectName.isEmpty && repoError == nil
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

    private func loadBranches() async {
        let path = repoPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            availableBranches = []
            repoError = nil
            return
        }

        let transport = LocalTransport()
        let git = GitService(transport: transport, repoPath: path)
        do {
            let branches = try await git.branches()
            availableBranches = branches
            repoError = nil

            let detected = try await git.defaultBranch()
            if availableBranches.contains(detected) {
                defaultBranch = detected
            } else if let first = branches.first {
                defaultBranch = first
            }
        } catch {
            availableBranches = []
            repoError = "Not a git repository"
        }

        // Auto-fill project name from folder name
        if projectName.isEmpty {
            projectName = URL(fileURLWithPath: path).lastPathComponent
        }
    }

    private func initializeRepo() {
        let path = repoPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        Task {
            let transport = LocalTransport()
            do {
                let result = try await transport.execute(
                    [GitService.resolveGitPath(), "init"],
                    in: path
                )
                if result.succeeded {
                    await loadBranches()
                } else {
                    repoError = "Failed to initialize: \(result.stderr)"
                }
            } catch {
                repoError = "Failed to initialize: \(error.localizedDescription)"
            }
        }
    }

    private func detectProjectConfig() async {
        isLoading = true
        defer { isLoading = false }

        let transport = LocalTransport()

        let git = GitService(transport: transport, repoPath: repoPath)

        // Only detect default branch if not already set from the picker
        if availableBranches.isEmpty, let branch = try? await git.defaultBranch() {
            defaultBranch = branch
        }

        // Detect existing worktrees
        if let worktrees = try? await git.worktreeList() {
            let filtered = worktrees.filter { !$0.isBare && $0.path != repoPath }
            detectedWorktrees = filtered
            selectedWorktreePaths = Set(filtered.map(\.path))
        }

        // Detect file presets that have matches in the repo
        let detected = FilePreset.detectPresets(in: repoPath)
        activePresets = Set(detected)
        filePatterns = detected.map(\.pattern)

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

    /// Returns an existing project that already uses this `repoPath`, or `nil`.
    private func existingProject(for path: String) -> Project? {
        let predicate = #Predicate<Project> { $0.repoPath == path }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    private func createBareProjectWithClaude(isExistingBranch: Bool) {
        let branchName = firstWorktreeBranch.trimmingCharacters(in: .whitespaces)
        guard !branchName.isEmpty else { return }

        errorMessage = nil

        Task {
            // 1. Create git worktree
            let transport = LocalTransport()
            let git = GitService(transport: transport, repoPath: repoPath)
            let existingWorktrees = (try? await git.worktreeList()) ?? []
            let existingPaths = Set(existingWorktrees.map(\.path))
            let worktreePath = WorktreePathResolver.resolve(
                basePath: worktreeBasePath,
                branchName: branchName,
                existingPaths: existingPaths
            )
            let alreadyExists = existingPaths.contains(worktreePath)

            if !alreadyExists {
                do {
                    if isExistingBranch {
                        try await git.worktreeAddExisting(
                            path: worktreePath,
                            branch: branchName
                        )
                    } else {
                        try await git.worktreeAdd(
                            path: worktreePath,
                            branch: branchName,
                            baseBranch: defaultBranch
                        )
                    }
                } catch {
                    errorMessage = "Failed to create worktree: \(error.localizedDescription)"
                    return
                }
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
                    worktreeBasePath: worktreeBasePath,
                    colorName: Project.nextColorName(in: modelContext),
                    sortOrder: Project.nextSortOrder(in: modelContext)
                )
                modelContext.insert(project)
            }
            project.needsClaudeConfig = true

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
            let nextWorktreeOrder = (project.worktrees.map(\.sortOrder).max() ?? -1) + 1
            let worktree = Worktree(
                branchName: branchName,
                path: worktreePath,
                baseBranch: defaultBranch,
                status: .ready,
                sortOrder: nextWorktreeOrder
            )
            worktree.project = project

            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save project with Claude setup: \(error.localizedDescription)")
            }

            // 4. Navigate to the new worktree and dismiss
            // (Claude config terminal is auto-launched by WorktreeColumnView when needsClaudeConfig is true)
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
                worktreeBasePath: worktreeBasePath,
                colorName: Project.nextColorName(in: modelContext),
                sortOrder: Project.nextSortOrder(in: modelContext)
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
        profile.filesToCopy = filePatterns
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
        var nextOrder = (project.worktrees.map(\.sortOrder).max() ?? -1) + 1
        for wt in detectedWorktrees where selectedWorktreePaths.contains(wt.path) {
            guard !existingPaths.contains(wt.path) else { continue }
            let branchName = wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent
            let worktree = Worktree(
                branchName: branchName,
                path: wt.path,
                baseBranch: defaultBranch,
                status: .ready,
                sortOrder: nextOrder
            )
            worktree.project = project
            nextOrder += 1
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save new project '\(projectName)': \(error.localizedDescription)")
        }

        // Write .wtmux/config.json and update .gitignore
        Task {
            let configService = ConfigService()
            let startCmd: String? = startClaudeInTerminals ? "claude" : (terminalStartCommand.isEmpty ? nil : terminalStartCommand)
            let config = ProjectConfig(
                filesToCopy: filePatterns,
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

    /// Patterns that aren't covered by any preset toggle.
    private var customPatterns: [String] {
        let presetPatterns = Set(FilePreset.allCases.map(\.pattern))
        return filePatterns.filter { !presetPatterns.contains($0) }
    }

    private func addCustomPattern() {
        let pattern = customPatternInput.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, !filePatterns.contains(pattern) else { return }
        filePatterns.append(pattern)
        customPatternInput = ""
    }

    private func enableClaudeIntegration() {
        claudeEnableError = nil
        do {
            try claudeIntegrationService.enableAll()
        } catch {
            if !claudeIntegrationService.canUseClaudeConfig {
                claudeEnableError = "Failed to enable: \(error.localizedDescription)"
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

private struct FirstWorktreeSheet: View {
    let availableBranches: [String]
    let onCancel: () -> Void
    let onCreate: (_ branch: String, _ isExisting: Bool) -> Void

    @State private var mode: WorktreeCreationMode = .newBranch
    @State private var newBranchName = ""
    @State private var selectedExistingBranch = ""

    private var effectiveBranch: String {
        switch mode {
        case .newBranch: newBranchName.trimmingCharacters(in: .whitespaces)
        case .existingBranch: selectedExistingBranch
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Create First Worktree")
                .font(.headline)

            Text("Choose a branch for your first worktree. Claude will auto-configure the project in the terminal.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Mode", selection: $mode) {
                ForEach(WorktreeCreationMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .newBranch:
                TextField("Branch name", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)

            case .existingBranch:
                Picker("Branch", selection: $selectedExistingBranch) {
                    Text("Select a branch").tag("")
                    ForEach(availableBranches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(mode == .existingBranch ? "Open" : "Create") {
                    onCreate(effectiveBranch, mode == .existingBranch)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(effectiveBranch.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

