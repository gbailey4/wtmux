import SwiftUI
import WTCore
import WTTerminal
import WTDiff
import WTGit
import WTTransport

struct WorktreeDetailView: View {
    let worktree: Worktree
    let terminalSessionManager: TerminalSessionManager
    @Binding var showRightPanel: Bool
    @Binding var showRunnerPanel: Bool

    @State private var diffFiles: [DiffFile] = []
    @State private var selectedDiffFile: DiffFile?
    @State private var showRunnerConflictAlert = false
    @State private var conflictingWorktreeName: String = ""
    @State private var conflictingPorts: [Int] = []

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
                } else if !configRunnerTabs.isEmpty || hasRunConfigurations {
                    Divider()
                    runnerStatusBar
                }
            }

            // Right panel: Diff viewer
            if showRightPanel {
                Divider()
                diffPanelView
                    .frame(width: 400)
            }
        }
        .task(id: worktreeId) {
            await ensureFirstTab()
            if showRightPanel {
                await loadDiff()
            }
        }
        .onChange(of: showRightPanel) { _, visible in
            if visible {
                Task { await loadDiff() }
            }
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
        guard let configs = worktree.project?.profile?.runConfigurations
            .sorted(by: { $0.order < $1.order }) else { return }
        for config in configs where !config.command.isEmpty {
            let sessionId = "runner-\(worktreeId)-\(config.name)"
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
                    TerminalRepresentable(session: session, isActive: active)
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
            if hasRunConfigurations {
                if configRunnerTabs.isEmpty {
                    Button {
                        startRunners()
                        showRunnerPanel = true
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help("Run All Configurations")
                }
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
                    terminalSessionManager.removeTab(sessionId: session.id)
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
                    TerminalRepresentable(session: session, isActive: active)
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

    // MARK: - Runner Status Bar

    @ViewBuilder
    private var runnerStatusBar: some View {
        let _ = terminalSessionManager.runnerStateVersion
        Button {
            if configRunnerTabs.isEmpty {
                startRunners()
            }
            showRunnerPanel = true
        } label: {
            HStack(spacing: 0) {
                if configRunnerTabs.isEmpty {
                    // No runners started yet — show available count
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                    Text(runConfigSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    runnerStatusSummary
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
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

    // MARK: - Diff Panel

    @ViewBuilder
    private var diffPanelView: some View {
        VStack(spacing: 0) {
            // File list header
            HStack {
                Text("Changes")
                    .font(.headline)
                Spacer()
                Text("\(diffFiles.count) files")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(8)
            .background(.bar)

            Divider()

            if diffFiles.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("No differences from \(worktree.baseBranch)")
                )
            } else {
                HSplitView {
                    // File list
                    List(diffFiles, selection: Binding(
                        get: { selectedDiffFile?.id },
                        set: { id in selectedDiffFile = diffFiles.first(where: { $0.id == id }) }
                    )) { file in
                        Text(file.displayPath)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .tag(file.id)
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 150)

                    // Diff content
                    if let file = selectedDiffFile {
                        InlineDiffView(file: file)
                    } else {
                        ContentUnavailableView(
                            "Select a File",
                            systemImage: "doc.text",
                            description: Text("Choose a file to view its diff")
                        )
                    }
                }
            }
        }
    }

    private func loadDiff() async {
        guard let project = worktree.project else { return }
        let transport = LocalTransport()
        let git = GitService(transport: transport, repoPath: project.repoPath)
        do {
            let diffOutput = try await git.diff(
                baseBranch: worktree.baseBranch,
                branch: worktree.branchName
            )
            let parser = DiffParser()
            diffFiles = parser.parse(diffOutput)
            selectedDiffFile = diffFiles.first
        } catch {
            diffFiles = []
        }
    }
}
