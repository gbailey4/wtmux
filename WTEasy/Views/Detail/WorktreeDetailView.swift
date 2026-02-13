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

    private var currentTheme: TerminalTheme {
        TerminalThemes.theme(forId: terminalThemeId)
    }

    private var worktreeId: String { worktree.branchName }

    private var terminalTabs: [TerminalSession] {
        terminalSessionManager.sessions(forWorktree: worktreeId)
            .filter { !$0.id.hasPrefix("runner-") }
    }

    private var activeTabId: String? {
        terminalSessionManager.activeSessionId[worktreeId]
    }

    private var allTabSessions: [TerminalSession] {
        terminalSessionManager.sessions.values
            .filter { !$0.worktreeId.isEmpty && !$0.id.hasPrefix("runner-") }
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
                    // Main terminal with tabs
                    tabbedTerminalView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom: Runner terminal panel
                    if showRunnerPanel && !allRunnerSessions.isEmpty {
                        Divider()
                        runnerTerminalsView
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 150, idealHeight: 250, maxHeight: 350)
                    } else if showRunnerPanel && hasRunConfigurations {
                        Divider()
                        runnerReadyView
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
            await ensureFirstTab()
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
                        launchAutoStartRunners()
                    }
                } label: {
                    Image(systemName: "play.rectangle")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Toggle Runner Panel (Cmd+Shift+R)")
            }
        }
    }

    private func ensureFirstTab() async {
        guard terminalSessionManager.sessions(forWorktree: worktreeId).isEmpty else { return }

        // Load config for start command and (optionally) setup commands
        var startCommand: String?
        if let repoPath = worktree.project?.repoPath {
            let applicator = ProfileApplicator()
            if let config = await applicator.loadConfig(forRepo: repoPath) {
                // Run setup commands in the runner panel on first creation
                if worktree.needsSetup == true {
                    let commands = config.setupCommands.filter { !$0.isEmpty }
                    if !commands.isEmpty {
                        let setupCommand = commands.joined(separator: " && ")
                        let session = terminalSessionManager.createSetupSession(
                            worktreeId: worktreeId,
                            workingDirectory: worktree.path,
                            command: setupCommand
                        )
                        session.onProcessExit = { [weak terminalSessionManager] sessionId, exitCode in
                            terminalSessionManager?.handleProcessExit(sessionId: sessionId, exitCode: exitCode)
                        }
                        showRunnerPanel = true
                    }
                }

                if let cmd = config.terminalStartCommand, !cmd.isEmpty {
                    startCommand = cmd
                }
            }
        }

        if worktree.needsSetup == true {
            worktree.needsSetup = false
        }

        // Create the main terminal tab with optional start command
        _ = terminalSessionManager.createTab(
            forWorktree: worktreeId,
            workingDirectory: worktree.path,
            initialCommand: startCommand
        )
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
            .map(\.branchName)
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
        for sibling in project.worktrees where sibling.branchName != worktreeId {
            for session in terminalSessionManager.runnerSessions(forWorktree: sibling.branchName) {
                terminalSessionManager.stopSession(id: session.id)
            }
            terminalSessionManager.removeRunnerSessions(forWorktree: sibling.branchName)
        }
        launchRunners()
    }

    private func launchRunners() {
        for config in runConfigurations where !config.command.isEmpty {
            launchSingleRunner(config: config)
        }
    }

    private func launchAutoStartRunners() {
        let autoStartConfigs = runConfigurations.filter { $0.autoStart && !$0.command.isEmpty }
        guard !autoStartConfigs.isEmpty else { return }
        // Check for conflicts before launching
        if let conflict = conflictingWorktree() {
            conflictingWorktreeName = conflict.name
            conflictingPorts = conflictingPortList()
            showRunnerConflictAlert = true
            return
        }
        for config in autoStartConfigs {
            launchSingleRunner(config: config)
        }
    }

    private func launchSingleRunner(config: RunConfiguration) {
        guard !config.command.isEmpty else { return }
        let sessionId = "runner-\(worktreeId)-\(config.name)"
        // Don't re-create if session already exists
        guard terminalSessionManager.sessions[sessionId] == nil else { return }
        let session = terminalSessionManager.createRunnerSession(
            id: sessionId,
            title: config.name,
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            initialCommand: config.command
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

    @ViewBuilder
    private var tabbedTerminalView: some View {
        VStack(spacing: 0) {
            terminalTabBar
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
            }
        }
    }

    @ViewBuilder
    private var terminalTabBar: some View {
        HStack(spacing: 0) {
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
                    launchAutoStartRunners()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("Open Runner Panel")
            }

            Button {
                Task {
                    var startCommand: String?
                    if let repoPath = worktree.project?.repoPath {
                        let applicator = ProfileApplicator()
                        if let config = await applicator.loadConfig(forRepo: repoPath),
                           let cmd = config.terminalStartCommand, !cmd.isEmpty {
                            startCommand = cmd
                        }
                    }
                    _ = terminalSessionManager.createTab(
                        forWorktree: worktreeId,
                        workingDirectory: worktree.path,
                        initialCommand: startCommand
                    )
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
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

            if terminalTabs.count > 1 {
                Button {
                    if session.terminalView?.hasChildProcesses() == true {
                        pendingCloseSessionId = session.id
                        showCloseTabAlert = true
                    } else {
                        terminalSessionManager.removeTab(sessionId: session.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(session.id == activeTabId ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    // MARK: - Runner Terminals

    @ViewBuilder
    private var runnerTerminalsView: some View {
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
            }
        }
    }

    @ViewBuilder
    private var runnerTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(runnerTabs) { session in
                        runnerTab(session: session)
                    }
                }
            }

            Spacer()

            if !configRunnerTabs.isEmpty {
                // Restart all
                Button {
                    restartAllRunners()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Restart All")

                // Stop all
                Button {
                    stopAllRunners()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Stop All")

                // Close/remove all runners
                Button {
                    removeAllRunners()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Close All Runners")
            }

            // Collapse chevron
            Button {
                showRunnerPanel = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption)
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
            } label: {
                Text(session.title)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            // Only show restart/stop for interactive runners (not command-mode sessions)
            if !session.runAsCommand {
                // Restart
                Button {
                    terminalSessionManager.restartSession(id: session.id)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .help("Restart")

                // Stop
                Button {
                    terminalSessionManager.stopSession(id: session.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .help("Stop")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(session.id == activeRunnerTabId ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    // MARK: - Runner Ready View

    @ViewBuilder
    private var runnerReadyView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Runners")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)

                Spacer()

                Button {
                    startRunners()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("Start All")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .help("Start All Runners")

                Button {
                    showRunnerPanel = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Collapse Runner Panel")
                .padding(.trailing, 4)
            }
            .padding(.vertical, 4)
            .background(.bar)

            ForEach(runConfigurations) { config in
                HStack(spacing: 8) {
                    Button {
                        if let conflict = conflictingWorktree() {
                            conflictingWorktreeName = conflict.name
                            conflictingPorts = conflictingPortList()
                            showRunnerConflictAlert = true
                        } else {
                            launchSingleRunner(config: config)
                        }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Start \(config.name)")

                    Text(config.name)
                        .font(.caption)
                        .lineLimit(1)

                    Text(config.command)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if config.autoStart {
                        Text("auto")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Runner Status Bar

    @ViewBuilder
    private var runnerStatusBar: some View {
        let _ = terminalSessionManager.runnerStateVersion
        Button {
            showRunnerPanel = true
            if configRunnerTabs.isEmpty {
                launchAutoStartRunners()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                if configRunnerTabs.isEmpty {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(runConfigSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    runnerStatusSummary
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
    }

    @ViewBuilder
    private var runnerStatusSummary: some View {
        let running = configRunnerTabs.filter { $0.state == .running }.count
        let failed = configRunnerTabs.filter { $0.state == .failed }.count
        let stopped = configRunnerTabs.filter { $0.state != .running && $0.state != .failed }.count

        HStack(spacing: 8) {
            if running > 0 {
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("\(running) running").font(.caption).foregroundStyle(.secondary)
                }
            }
            if failed > 0 {
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("\(failed) failed").font(.caption).foregroundStyle(.secondary)
                }
            }
            if stopped > 0 && (running > 0 || failed > 0) {
                HStack(spacing: 3) {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                    Text("\(stopped) stopped").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var runConfigSummaryText: String {
        let count = worktree.project?.profile?.runConfigurations.count ?? 0
        return "\(count) runner\(count == 1 ? "" : "s") available"
    }

}
