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

    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id

    @State private var activeDiffFile: DiffFile?
    @State private var showRunnerConflictAlert = false
    @State private var conflictingWorktreeName: String = ""
    @State private var conflictingPorts: [Int] = []
    @State private var showCloseTabAlert = false
    @State private var pendingCloseSessionId: String?
    @State private var showSetupBanner = false

    private var currentTheme: TerminalTheme {
        TerminalThemes.theme(forId: terminalThemeId)
    }

    private var worktreeId: String { worktree.path }

    private var terminalTabs: [TerminalSession] {
        terminalSessionManager.sessions(forWorktree: worktreeId)
            .filter { !SessionID.isRunner($0.id) }
    }

    private var activeTabId: String? {
        terminalSessionManager.activeSessionId[worktreeId]
    }

    private var allTabSessions: [TerminalSession] {
        terminalSessionManager.sessions.values
            .filter { !$0.worktreeId.isEmpty && !SessionID.isRunner($0.id) }
            .sorted { $0.id < $1.id }
    }

    private var runConfigurations: [RunConfiguration] {
        worktree.project?.profile?.runConfigurations
            .sorted(by: { $0.order < $1.order }) ?? []
    }

    private var runnerTabs: [TerminalSession] {
        terminalSessionManager.runnerSessions(forWorktree: worktreeId)
    }

    /// Runner tabs that correspond to run configurations (excludes setup sessions).
    private var configRunnerTabs: [TerminalSession] {
        runnerTabs.filter { !$0.runAsCommand }
    }

    private var activeRunnerTabId: String? {
        terminalSessionManager.activeRunnerSessionId[worktreeId]
    }

    private var allRunnerSessions: [TerminalSession] {
        terminalSessionManager.allRunnerSessions()
    }

    private var hasRunConfigurations: Bool {
        !(worktree.project?.profile?.runConfigurations.isEmpty ?? true)
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                // Center: Main terminal tabs + runner terminals
                VStack(spacing: 0) {
                    // Setup banner (inline, no safeAreaInset)
                    if showSetupBanner, let commands = worktree.project?.profile?.setupCommands,
                       !commands.filter({ !$0.isEmpty }).isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Setup Available")
                                    .font(.subheadline.bold())
                                Text(commands.joined(separator: " && "))
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
        let commands = (worktree.project?.profile?.setupCommands ?? []).filter { !$0.isEmpty }
        guard !commands.isEmpty else { return }
        let setupCommand = commands.joined(separator: " && ")
        let session = terminalSessionManager.createSetupSession(
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            command: setupCommand
        )
        session.onProcessExit = { [weak terminalSessionManager] sessionId, exitCode in
            terminalSessionManager?.handleProcessExit(sessionId: sessionId, exitCode: exitCode)
        }
        worktree.needsSetup = false
        showRunnerPanel = true
        ensureRunnerSessions()
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
                // All tab sessions across ALL worktrees live here so
                // terminal views (and their PTY processes) survive
                // worktree switches.  Only the active tab is visible.
                ForEach(allTabSessions) { session in
                    let active = session.id == activeTabId
                    TerminalRepresentable(session: session, isActive: active, theme: currentTheme)
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
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
            Button {
                terminalSessionManager.setActiveSession(worktreeId: worktreeId, sessionId: session.id)
            } label: {
                Text(session.title)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

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
    }

    // MARK: - Runner Terminals

    @ViewBuilder
    private var runnerTerminalsView: some View {
        let _ = terminalSessionManager.runnerStateVersion
        let activeSession = activeRunnerTabId.flatMap { terminalSessionManager.session(for: $0) }
        VStack(spacing: 0) {
            runnerTabBar
            ZStack {
                // Persist all runner sessions across worktree switches
                ForEach(allRunnerSessions) { session in
                    let active = session.id == activeRunnerTabId
                    TerminalRepresentable(session: session, isActive: active, theme: currentTheme)
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
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
                    ForEach(runnerTabs) { session in
                        runnerTab(session: session)
                    }
                }
            }

            Spacer()

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
