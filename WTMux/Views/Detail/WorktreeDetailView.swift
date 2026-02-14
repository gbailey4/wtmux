import SwiftUI
import WTCore
import WTDiff
import WTGit
import WTTerminal
import WTTransport

struct WorktreeDetailView: View {
    let worktree: Worktree
    let terminalSessionManager: TerminalSessionManager
    @Binding var showRightPanel: Bool
    @Binding var showRunnerPanel: Bool
    @Binding var changedFileCount: Int
    var isPaneFocused: Bool = true

    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id

    @State private var activeDiffFile: DiffFile?
    @State private var showRunnerConflictAlert = false
    @State private var conflictingWorktreeName: String = ""
    @State private var conflictingPorts: [Int] = []
    @State private var showCloseTabAlert = false
    @State private var pendingCloseSessionId: String?
    @State private var showSetupBanner = false
    @State private var showConfigPendingBanner = false
    @State private var showRerunSetupSheet = false
    @State private var suppressSetupConfirm = false
    @State private var lastActiveSetupSessionId: [String: String] = [:]
    @State private var renamingTabId: String?
    @State private var renameText: String = ""
    @State private var renameError: Bool = false
    @FocusState private var isRenameFieldFocused: Bool

    private var currentTheme: TerminalTheme {
        TerminalThemes.theme(forId: terminalThemeId)
    }

    private var worktreeId: String { worktree.path }

    private var terminalTabs: [TerminalSession] {
        terminalSessionManager.orderedSessions(forWorktree: worktreeId)
    }

    private var activeTabId: String? {
        terminalSessionManager.activeSessionId[worktreeId]
    }

    private var runConfigurations: [RunConfiguration] {
        worktree.project?.profile?.runConfigurations
            .sorted(by: { $0.order < $1.order }) ?? []
    }

    private var runnerTabs: [TerminalSession] {
        terminalSessionManager.runnerSessions(forWorktree: worktreeId)
    }

    /// Runner tabs for setup commands (runAsCommand sessions).
    private var setupRunnerTabs: [TerminalSession] {
        runnerTabs.filter { SessionID.isSetup($0.id) }
    }

    /// Runner tabs that correspond to run configurations (excludes setup sessions).
    /// Sorted: auto-start runners first, then optional, each sub-group by order.
    private var configRunnerTabs: [TerminalSession] {
        runnerTabs
            .filter { !SessionID.isSetup($0.id) }
            .sorted { a, b in
                let configA = runConfiguration(for: a)
                let configB = runConfiguration(for: b)
                let autoA = configA?.autoStart ?? false
                let autoB = configB?.autoStart ?? false
                if autoA != autoB { return autoA }  // auto-start first
                return (configA?.order ?? .max) < (configB?.order ?? .max)
            }
    }

    /// Whether the active runner tab is a setup session.
    private var isSetupGroupActive: Bool {
        guard let activeId = activeRunnerTabId else { return false }
        return SessionID.isSetup(activeId)
    }

    /// Aggregate state across all setup sessions: failed > running > succeeded > idle.
    private var setupGroupState: SessionState {
        let tabs = setupRunnerTabs
        if tabs.contains(where: { $0.state == .failed }) { return .failed }
        if tabs.contains(where: { $0.state == .running }) { return .running }
        if tabs.allSatisfy({ $0.state == .succeeded }) && !tabs.isEmpty { return .succeeded }
        return .idle
    }

    /// Label like "2/3" showing completed setup commands vs total.
    private var setupGroupLabel: String {
        let total = setupRunnerTabs.count
        let done = setupRunnerTabs.filter { $0.state == .succeeded || $0.state == .failed }.count
        return "\(done)/\(total)"
    }

    /// Whether setup commands exist on the profile (regardless of whether sessions are running).
    private var hasSetupCommands: Bool {
        guard let commands = worktree.project?.profile?.setupCommands else { return false }
        return !commands.filter({ !$0.isEmpty }).isEmpty
    }

    private var activeRunnerTabId: String? {
        terminalSessionManager.activeRunnerSessionId[worktreeId]
    }

    private var hasRunConfigurations: Bool {
        !(worktree.project?.profile?.runConfigurations.isEmpty ?? true)
    }

    private var isClaudeConfigRunning: Bool {
        terminalSessionManager.sessions(forWorktree: worktreeId).contains { session in
            session.initialCommand?.contains("configure_project") == true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                // Center: Main terminal tabs + runner terminals
                VStack(spacing: 0) {
                    // Configuration pending banner
                    if showConfigPendingBanner, worktree.project?.needsClaudeConfig == true, !isClaudeConfigRunning {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Configuration Pending")
                                    .font(.subheadline.bold())
                                Text("Claude hasn't finished configuring this project yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Configure with Claude") {
                                showConfigPendingBanner = false
                                openClaudeConfigTerminal()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(!claudeIntegrationService.canUseClaudeConfig)
                            Button {
                                showConfigPendingBanner = false
                                worktree.project?.needsClaudeConfig = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(.orange.opacity(0.1))
                        Divider()
                    }

                    // Setup banner (inline, no safeAreaInset)
                    if showSetupBanner, let commands = worktree.project?.profile?.setupCommands,
                       !commands.filter({ !$0.isEmpty }).isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Setup Available")
                                    .font(.subheadline.bold())
                                Text(commands.count == 1 ? commands[0] : "\(commands.count) setup commands")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Run Setup") {
                                showSetupBanner = false
                                runSetup()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            Button {
                                showSetupBanner = false
                                worktree.needsSetup = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(.blue.opacity(0.1))
                        Divider()
                    }

                    // Main terminal with tabs
                    tabbedTerminalView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom: Runner terminal panel
                    if showRunnerPanel && (!runnerTabs.isEmpty || hasRunConfigurations) {
                        Divider()
                        runnerTerminalsView
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 150, idealHeight: 250, maxHeight: 350)
                    } else if !configRunnerTabs.isEmpty || hasRunConfigurations {
                        Divider()
                        runnerStatusBar
                    }
                }

                // Diff overlay — shown when a file is selected from the outline
                if let file = activeDiffFile {
                    DiffContentView(
                        file: file,
                        onClose: { activeDiffFile = nil },
                        backgroundColor: currentTheme.background.toColor(),
                        foregroundColor: currentTheme.foreground.toColor()
                    ) {
                        openInEditorMenu(relativePath: file.displayPath)
                    }
                    .environment(\.colorScheme, currentTheme.isDark ? .dark : .light)
                }
            }

            // Right panel: Changes outline
            if showRightPanel {
                Divider()
                ChangesPanel(worktree: worktree, activeDiffFile: $activeDiffFile, changedFileCount: $changedFileCount)
                    .frame(width: 400)
            }
        }
        .task(id: worktreeId) {
            activeDiffFile = nil
            changedFileCount = 0
            showConfigPendingBanner = worktree.project?.needsClaudeConfig == true
            ensureFirstTab()
            if showRunnerPanel && hasRunConfigurations {
                ensureRunnerSessions()
            }
            let git = GitService(transport: LocalTransport(), repoPath: worktree.path)
            if let files = try? await git.status() {
                changedFileCount = files.count
            }
        }
        .alert("Close Terminal?", isPresented: $showCloseTabAlert) {
            Button("Close", role: .destructive) {
                if let id = pendingCloseSessionId {
                    terminalSessionManager.removeTab(sessionId: id)
                    pendingCloseSessionId = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCloseSessionId = nil
            }
        } message: {
            Text("This terminal has a running process. Closing it will terminate the process.")
        }
        .alert("Runners Already Active", isPresented: $showRunnerConflictAlert) {
            Button("Stop & Switch") {
                stopConflictingAndStartRunners()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if conflictingPorts.isEmpty {
                Text("Worktree \"\(conflictingWorktreeName)\" is already running. Starting runners here may cause port conflicts.")
            } else {
                let ports = conflictingPorts.map(String.init).joined(separator: ", ")
                Text("Worktree \"\(conflictingWorktreeName)\" is already using port\(conflictingPorts.count > 1 ? "s" : "") \(ports). Stop its runners and start here instead?")
            }
        }
        .sheet(isPresented: $showRerunSetupSheet) {
            RerunSetupSheet(
                suppressConfirm: $suppressSetupConfirm,
                onRun: {
                    if suppressSetupConfirm {
                        worktree.project?.profile?.confirmSetupRerun = false
                    }
                    showRerunSetupSheet = false
                    runSetup()
                },
                onCancel: { showRerunSetupSheet = false }
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showRunnerPanel.toggle()
                    if showRunnerPanel {
                        ensureRunnerSessions()
                        launchRunners()
                    }
                } label: {
                    Image(systemName: "play.rectangle")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Toggle Runner Panel (Cmd+Shift+R)")
            }
        }
        .onChange(of: worktree.needsSetup) { _, newValue in
            if newValue == true {
                showSetupBanner = true
            }
        }
        .onChange(of: worktree.project?.needsClaudeConfig) { _, newValue in
            if newValue == true {
                showConfigPendingBanner = true
            } else if newValue == false {
                showConfigPendingBanner = false
            }
        }
    }

    private func openClaudeConfigTerminal() {
        guard let repoPath = worktree.project?.repoPath else { return }
        ClaudeConfigHelper.openConfigTerminal(
            terminalSessionManager: terminalSessionManager,
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            repoPath: repoPath
        )
    }

    private func ensureFirstTab() {
        guard terminalSessionManager.sessions(forWorktree: worktreeId).isEmpty else { return }

        // Run setup commands in the runner panel on first creation
        if worktree.needsSetup == true {
            runSetup()
        }

        let startCommand: String? = {
            guard let cmd = worktree.project?.profile?.terminalStartCommand, !cmd.isEmpty else { return nil }
            return cmd
        }()

        // Create the main terminal tab with optional start command
        _ = terminalSessionManager.createTab(
            forWorktree: worktreeId,
            workingDirectory: worktree.path,
            initialCommand: startCommand
        )
    }

    private func runSetup() {
        showSetupBanner = false
        let commands = (worktree.project?.profile?.setupCommands ?? []).filter { !$0.isEmpty }
        guard !commands.isEmpty else { return }
        // Clean up any previous setup sessions before (re)running
        terminalSessionManager.removeSetupSessions(forWorktree: worktreeId)
        let sessions = terminalSessionManager.createSetupSessions(
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            commands: commands
        )
        for session in sessions {
            session.onProcessExit = { [weak terminalSessionManager] sessionId, exitCode in
                terminalSessionManager?.handleProcessExit(sessionId: sessionId, exitCode: exitCode)
            }
        }
        worktree.needsSetup = false
        showRunnerPanel = true
        if let firstId = sessions.first?.id {
            lastActiveSetupSessionId[worktreeId] = firstId
        }
        ensureRunnerSessions()
    }

    private func confirmAndRunSetup() {
        guard worktree.project?.profile?.confirmSetupRerun != false else {
            runSetup()
            return
        }
        suppressSetupConfirm = false
        showRerunSetupSheet = true
    }

    // MARK: - Open In Editor

    @ViewBuilder
    private func openInEditorMenu(relativePath: String) -> some View {
        let editors = ExternalEditor.installedEditors(custom: ExternalEditor.customEditors)
        Menu {
            ForEach(editors) { editor in
                Button(editor.name) {
                    let fileURL = URL(fileURLWithPath: worktree.path)
                        .appendingPathComponent(relativePath)
                    ExternalEditor.open(fileURL: fileURL, editor: editor)
                }
            }
            Divider()
            SettingsLink {
                Text("Configure Editors...")
            }
        } label: {
            Image(systemName: "arrow.up.forward.square")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Run Actions

    private func startRunners() {
        // Check for runners already active on another worktree in the same project
        if let conflict = conflictingWorktree() {
            conflictingWorktreeName = conflict.name
            conflictingPorts = conflictingPortList()
            showRunnerConflictAlert = true
            return
        }
        launchRunners()
    }

    /// Finds another worktree in the same project that has running runners.
    private func conflictingWorktree() -> (name: String, id: String)? {
        guard let project = worktree.project else { return nil }
        let _ = terminalSessionManager.runnerStateVersion
        let siblingIds = project.worktrees
            .map(\.path)
            .filter { $0 != worktreeId }
        for siblingId in siblingIds {
            let runners = terminalSessionManager.runnerSessions(forWorktree: siblingId)
            if runners.contains(where: { $0.isProcessRunning }) {
                return (name: siblingId, id: siblingId)
            }
        }
        return nil
    }

    /// Returns ports configured for this project's run configurations.
    private func conflictingPortList() -> [Int] {
        guard let configs = worktree.project?.profile?.runConfigurations else { return [] }
        return configs.compactMap(\.port).sorted()
    }

    private func stopConflictingAndStartRunners() {
        guard let project = worktree.project else { return }
        // Stop runners on all other worktrees in this project
        for sibling in project.worktrees where sibling.path != worktreeId {
            for session in terminalSessionManager.runnerSessions(forWorktree: sibling.path) {
                terminalSessionManager.stopSession(id: session.id)
            }
            terminalSessionManager.removeRunnerSessions(forWorktree: sibling.path)
        }
        launchRunners()
    }

    private func launchRunners() {
        ensureRunnerSessions()
        let defaultConfigs = runConfigurations.filter { $0.autoStart && !$0.command.isEmpty }
        for config in defaultConfigs {
            let sessionId = SessionID.runner(worktreeId: worktreeId, name: config.name)
            terminalSessionManager.startSession(id: sessionId)
        }
    }

    private func launchSingleRunner(config: RunConfiguration) {
        guard !config.command.isEmpty else { return }
        let sessionId = SessionID.runner(worktreeId: worktreeId, name: config.name)
        ensureRunnerSession(config: config)
        terminalSessionManager.startSession(id: sessionId)
    }

    /// Creates idle (deferred) runner sessions for all configs that don't already have sessions.
    private func ensureRunnerSessions() {
        for config in runConfigurations where !config.command.isEmpty {
            ensureRunnerSession(config: config)
        }
    }

    /// Creates a single idle runner session for a config if one doesn't already exist.
    private func ensureRunnerSession(config: RunConfiguration) {
        let sessionId = SessionID.runner(worktreeId: worktreeId, name: config.name)
        guard terminalSessionManager.sessions[sessionId] == nil else { return }
        let session = terminalSessionManager.createRunnerSession(
            id: sessionId,
            title: config.name,
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            initialCommand: config.command,
            deferExecution: true
        )
        session.onProcessExit = { [weak terminalSessionManager] sessionId, exitCode in
            terminalSessionManager?.handleProcessExit(sessionId: sessionId, exitCode: exitCode)
        }
    }

    private func stopAllRunners() {
        for session in configRunnerTabs {
            terminalSessionManager.stopSession(id: session.id)
        }
    }

    private func restartAllRunners() {
        for session in configRunnerTabs {
            terminalSessionManager.restartSession(id: session.id)
        }
    }

    private func removeAllRunners() {
        terminalSessionManager.removeRunnerSessions(forWorktree: worktreeId)
    }

    // MARK: - Tabbed Terminal

    private func createNewTerminalTab() {
        let startCommand: String? = {
            guard let cmd = worktree.project?.profile?.terminalStartCommand, !cmd.isEmpty else { return nil }
            return cmd
        }()
        _ = terminalSessionManager.createTab(
            forWorktree: worktreeId,
            workingDirectory: worktree.path,
            initialCommand: startCommand
        )
    }

    @ViewBuilder
    private var tabbedTerminalView: some View {
        VStack(spacing: 0) {
            if !terminalTabs.isEmpty {
                terminalTabBar
            }
            ZStack {
                ForEach(terminalTabs) { session in
                    let isActiveTab = session.id == activeTabId
                    TerminalRepresentable(session: session, isActive: isActiveTab && isPaneFocused, theme: currentTheme)
                        .opacity(isActiveTab ? 1 : 0)
                        .allowsHitTesting(isActiveTab)
                }
                if terminalTabs.isEmpty {
                    ContentUnavailableView {
                        Label("No Terminal", systemImage: "terminal")
                    } description: {
                        Text("Open a new terminal to get started.")
                    } actions: {
                        Button("New Terminal") {
                            createNewTerminalTab()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var terminalTabBar: some View {
        HStack(spacing: 0) {
            if let projectName = worktree.project?.name {
                HStack(spacing: 4) {
                    Text(projectName)
                        .foregroundStyle(.secondary)
                    Text("/")
                        .foregroundStyle(.tertiary)
                    Text(worktree.branchName)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 10)

                Divider()
                    .frame(height: 14)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(terminalTabs) { session in
                        terminalTab(session: session)
                    }
                }
            }

            Spacer()

            // Run button
            if hasRunConfigurations && configRunnerTabs.isEmpty {
                Button {
                    showRunnerPanel = true
                    ensureRunnerSessions()
                    launchRunners()
                }                 label: {
                    Image(systemName: "play.fill")
                        .font(.subheadline)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("Open Runner Panel")
            }

            Button {
                createNewTerminalTab()
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func terminalTab(session: TerminalSession) -> some View {
        HStack(spacing: 4) {
            if renamingTabId == session.id {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Tab name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1)
                        .frame(minWidth: 60, maxWidth: 120)
                        .focused($isRenameFieldFocused)
                        .onSubmit { commitRename(sessionId: session.id) }
                        .onChange(of: isRenameFieldFocused) { _, focused in
                            if !focused { commitRename(sessionId: session.id) }
                        }
                        .onChange(of: renameText) { _, _ in renameError = false }
                        .onKeyPress(.escape) {
                            cancelRename()
                            return .handled
                        }
                    if renameError {
                        Text("Name already in use")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Text(session.title)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        startRename(session: session)
                    }
                    .onTapGesture(count: 1) {
                        terminalSessionManager.setActiveSession(worktreeId: worktreeId, sessionId: session.id)
                    }
            }

            Button {
                if session.terminalView?.hasChildProcesses() == true {
                    pendingCloseSessionId = session.id
                    showCloseTabAlert = true
                } else {
                    terminalSessionManager.removeTab(sessionId: session.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(session.id == activeTabId ? Color.accentColor.opacity(0.2) : Color.clear)
        .draggable(session.id)
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let droppedId = droppedIds.first,
                  droppedId != session.id,
                  let targetIndex = terminalTabs.firstIndex(where: { $0.id == session.id }) else { return false }
            terminalSessionManager.moveTab(sessionId: droppedId, toIndex: targetIndex, inWorktree: worktreeId)
            return true
        }
    }

    private func startRename(session: TerminalSession) {
        renameText = session.title
        renamingTabId = session.id
        isRenameFieldFocused = true
    }

    private func commitRename(sessionId: String) {
        guard renamingTabId == sessionId else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            if !terminalSessionManager.renameTab(sessionId: sessionId, to: trimmed) {
                renameError = true
                return
            }
        }
        renameError = false
        renamingTabId = nil
    }

    private func cancelRename() {
        renamingTabId = nil
    }

    // MARK: - Runner Terminals

    @ViewBuilder
    private var runnerTerminalsView: some View {
        let _ = terminalSessionManager.runnerStateVersion
        let activeSession = activeRunnerTabId.flatMap { terminalSessionManager.session(for: $0) }
        VStack(spacing: 0) {
            runnerTabBar
            if isSetupGroupActive && setupRunnerTabs.count > 1 {
                setupSubTabBar
            }
            ZStack {
                ForEach(runnerTabs) { session in
                    let isActiveRunner = session.id == activeRunnerTabId
                    TerminalRepresentable(session: session, isActive: isActiveRunner && isPaneFocused, theme: currentTheme)
                        .opacity(isActiveRunner ? 1 : 0)
                        .allowsHitTesting(isActiveRunner)
                }

                // Play overlay for idle/deferred sessions
                if let session = activeSession, session.deferExecution {
                    Color.black.opacity(0.4)
                        .allowsHitTesting(true)
                        .onHover { inside in
                            if inside { NSCursor.arrow.push() } else { NSCursor.pop() }
                        }
                    Button {
                        if let conflict = conflictingWorktree() {
                            conflictingWorktreeName = conflict.name
                            conflictingPorts = conflictingPortList()
                            showRunnerConflictAlert = true
                        } else {
                            terminalSessionManager.startSession(id: session.id)
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                            Text("Start \(session.title)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .padding(20)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var runnerTabBar: some View {
        let _ = terminalSessionManager.runnerStateVersion
        let hasIdleDefaultSessions = configRunnerTabs.contains { session in
            session.deferExecution && (runConfiguration(for: session)?.autoStart ?? true)
        }
        let hasStartedSessions = configRunnerTabs.contains { !$0.deferExecution }
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Setup group tab (single tab replacing individual setup tabs)
                    if !setupRunnerTabs.isEmpty {
                        setupGroupTab
                    }
                    ForEach(configRunnerTabs) { session in
                        runnerTab(session: session)
                    }
                }
            }

            Spacer()

            // "Run Setup" button when setup commands exist but sessions have been dismissed
            if setupRunnerTabs.isEmpty && hasSetupCommands {
                Button {
                    confirmAndRunSetup()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text("Run Setup")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .help("Run Setup Commands")
            }

            if hasIdleDefaultSessions {
                // Start default runners
                Button {
                    startRunners()
                }                 label: {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Start Default")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .help("Start Default Runners")
            }

            if hasStartedSessions {
                // Restart all
                Button {
                    restartAllRunners()
                }                 label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Restart All")

                // Stop all
                Button {
                    stopAllRunners()
                }                 label: {
                    Image(systemName: "stop.fill")
                        .font(.subheadline)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Stop All")

                // Close/remove all runners
                Button {
                    removeAllRunners()
                }                 label: {
                    Image(systemName: "xmark.circle")
                        .font(.subheadline)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Close All Runners")
            }

            // Collapse chevron
            Button {
                showRunnerPanel = false
            }             label: {
                Image(systemName: "chevron.down")
                    .font(.subheadline)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Collapse Runner Panel")
            .padding(.trailing, 4)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func runnerTab(session: TerminalSession) -> some View {
        // Read runnerStateVersion so SwiftUI re-renders when stop/restart is called
        let _ = terminalSessionManager.runnerStateVersion
        HStack(spacing: 4) {
            // State indicator
            switch session.state {
            case .running:
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            case .idle:
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
            }

            Button {
                terminalSessionManager.setActiveRunnerSession(worktreeId: worktreeId, sessionId: session.id)
            } label: {
                Text(session.title)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            // Port badges
            ForEach(session.listeningPorts.sorted(), id: \.self) { port in
                HStack(spacing: 2) {
                    Button {
                        if let url = URL(string: "http://localhost:\(port)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text(":\(port)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Open http://localhost:\(port)")

                    // Save-to-config action
                    if let config = runConfiguration(for: session),
                       config.port != Int(port) {
                        Button {
                            config.port = Int(port)
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Save port to run configuration")
                    }
                }
            }

            // Only show controls for interactive runners (not command-mode sessions)
            if !session.runAsCommand {
                if session.deferExecution {
                    // Play — start the deferred command
                    Button {
                        if let conflict = conflictingWorktree() {
                            conflictingWorktreeName = conflict.name
                            conflictingPorts = conflictingPortList()
                            showRunnerConflictAlert = true
                        } else {
                            terminalSessionManager.startSession(id: session.id)
                        }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Start")
                } else {
                    // Restart
                    Button {
                        terminalSessionManager.restartSession(id: session.id)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Restart")

                    // Stop
                    Button {
                        terminalSessionManager.stopSession(id: session.id)
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .opacity(isDefaultRunner(session) ? 1.0 : 0.6)
        .background(session.id == activeRunnerTabId ? Color.accentColor.opacity(0.2) : Color.clear)
        .draggable(session.id)
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let droppedId = droppedIds.first, droppedId != session.id else { return false }
            reorderRunnerConfig(droppedSessionId: droppedId, targetSessionId: session.id)
            return true
        }
    }

    /// Reorders runner configurations via drag/drop within the same group (auto-start or optional).
    private func reorderRunnerConfig(droppedSessionId: String, targetSessionId: String) {
        guard let droppedSession = terminalSessionManager.session(for: droppedSessionId),
              let targetSession = terminalSessionManager.session(for: targetSessionId),
              let droppedConfig = runConfiguration(for: droppedSession),
              let targetConfig = runConfiguration(for: targetSession) else { return }

        // Only allow reorder within the same group
        guard droppedConfig.autoStart == targetConfig.autoStart else { return }

        let isAutoStart = droppedConfig.autoStart
        var groupConfigs = runConfigurations
            .filter { $0.autoStart == isAutoStart }
            .sorted { $0.order < $1.order }

        guard let fromIndex = groupConfigs.firstIndex(where: { $0.name == droppedConfig.name }),
              let toIndex = groupConfigs.firstIndex(where: { $0.name == targetConfig.name }) else { return }

        let moved = groupConfigs.remove(at: fromIndex)
        groupConfigs.insert(moved, at: toIndex)

        // Reassign order values; offset optional group so they sort after auto-start
        let baseOffset = isAutoStart ? 0 : 1000
        for (index, config) in groupConfigs.enumerated() {
            config.order = baseOffset + index
        }
    }

    // MARK: - Setup Group Tab

    @ViewBuilder
    private var setupGroupTab: some View {
        let _ = terminalSessionManager.runnerStateVersion
        let allDone = setupRunnerTabs.allSatisfy({ $0.state == .succeeded || $0.state == .failed })
        HStack(spacing: 4) {
            // State indicator
            switch setupGroupState {
            case .running:
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            case .idle:
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
            }

            Button {
                activateSetupGroup()
            } label: {
                HStack(spacing: 2) {
                    Text("Setup")
                        .lineLimit(1)
                    Text("(\(setupGroupLabel))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if allDone {
                // Rerun
                Button {
                    confirmAndRunSetup()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Rerun Setup")

                // Dismiss
                Button {
                    terminalSessionManager.removeSetupSessions(forWorktree: worktreeId)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Dismiss Setup")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSetupGroupActive ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    private func activateSetupGroup() {
        // Restore last-viewed setup sub-tab, or fall back to first
        let targetId = lastActiveSetupSessionId[worktreeId] ?? setupRunnerTabs.first?.id
        if let id = targetId {
            terminalSessionManager.setActiveRunnerSession(worktreeId: worktreeId, sessionId: id)
        }
    }

    @ViewBuilder
    private var setupSubTabBar: some View {
        let _ = terminalSessionManager.runnerStateVersion
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(setupRunnerTabs) { session in
                        setupSubTab(session: session)
                    }
                }
            }
            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private func setupSubTab(session: TerminalSession) -> some View {
        let _ = terminalSessionManager.runnerStateVersion
        HStack(spacing: 3) {
            // State indicator (smaller)
            switch session.state {
            case .running:
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 10))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 10))
            case .idle:
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
            }

            Button {
                terminalSessionManager.setActiveRunnerSession(worktreeId: worktreeId, sessionId: session.id)
                lastActiveSetupSessionId[worktreeId] = session.id
            } label: {
                Text(session.title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(session.id == activeRunnerTabId ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    private func isDefaultRunner(_ session: TerminalSession) -> Bool {
        runConfiguration(for: session)?.autoStart ?? true
    }

    // MARK: - Runner Status Bar

    @ViewBuilder
    private var runnerStatusBar: some View {
        let _ = terminalSessionManager.runnerStateVersion
        Button {
            showRunnerPanel = true
            ensureRunnerSessions()
            if configRunnerTabs.isEmpty {
                launchRunners()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                if configRunnerTabs.isEmpty {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(runConfigSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    runnerStatusSummary
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
    }

    @ViewBuilder
    private var runnerStatusSummary: some View {
        let running = configRunnerTabs.filter { $0.state == .running }.count
        let failed = configRunnerTabs.filter { $0.state == .failed }.count
        let idle = configRunnerTabs.filter { $0.deferExecution }.count
        let stopped = configRunnerTabs.filter { !$0.deferExecution && $0.state != .running && $0.state != .failed }.count

        HStack(spacing: 8) {
            if running > 0 {
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("\(running) running").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if failed > 0 {
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("\(failed) failed").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if stopped > 0 {
                HStack(spacing: 3) {
                    Circle().fill(.secondary).frame(width: 8, height: 8)
                    Text("\(stopped) stopped").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if idle > 0 && idle == configRunnerTabs.count {
                Text(runConfigSummaryText).font(.subheadline).foregroundStyle(.secondary)
            }

            // Aggregate listening ports across all running runners
            let allPorts = configRunnerTabs.flatMap(\.listeningPorts).sorted()
            if !allPorts.isEmpty {
                HStack(spacing: 3) {
                    ForEach(allPorts, id: \.self) { port in
                        Text(":\(port)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
    }

    private var runConfigSummaryText: String {
        let configs = worktree.project?.profile?.runConfigurations ?? []
        let defaultCount = configs.filter(\.autoStart).count
        let optionalCount = configs.count - defaultCount
        if defaultCount > 0 && optionalCount > 0 {
            return "\(defaultCount) default + \(optionalCount) optional"
        } else if optionalCount > 0 {
            return "\(optionalCount) optional runner\(optionalCount == 1 ? "" : "s")"
        }
        return "\(configs.count) runner\(configs.count == 1 ? "" : "s") available"
    }

    private func runConfiguration(for session: TerminalSession) -> RunConfiguration? {
        runConfigurations.first { $0.name == session.title }
    }

}

// MARK: - Rerun Setup Sheet

struct RerunSetupSheet: View {
    @Binding var suppressConfirm: Bool
    let onRun: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("Re-run Project Setup?")
                .font(.headline)

            Text("This will re-run all setup commands for this worktree.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Don't ask again for this project", isOn: $suppressConfirm)
                .padding(.horizontal)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Run Setup", action: onRun)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
