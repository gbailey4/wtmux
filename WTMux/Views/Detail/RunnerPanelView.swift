import AppKit
import SwiftUI
import WTCore
import WTTerminal
import WTSSH

/// Self-contained runner panel view that handles both expanded (terminal) and collapsed (status bar) states.
/// Placed at the column level so runners are shared across all panes showing the same worktree.
struct RunnerPanelView: View {
    let worktree: Worktree
    let terminalSessionManager: TerminalSessionManager
    @Binding var showRunnerPanel: Bool
    var isPaneFocused: Bool = true

    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @Environment(\.sshConnectionManager) private var sshConnectionManager
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id

    @State private var showRunnerConflictAlert = false
    @State private var conflictingWorktreeName: String = ""
    @State private var conflictingPorts: [Int] = []
    @State private var showRerunSetupSheet = false
    @State private var suppressSetupConfirm = false
    @State private var lastActiveSetupSessionId: [String: String] = [:]

    private var currentTheme: TerminalTheme {
        TerminalThemes.theme(forId: terminalThemeId)
    }

    private var worktreeId: String { worktree.path }

    private var runConfigurations: [RunConfiguration] {
        worktree.project?.profile?.runConfigurations
            .sorted(by: { $0.order < $1.order }) ?? []
    }

    private var runnerTabs: [TerminalSession] {
        terminalSessionManager.runnerSessions(forWorktree: worktreeId)
    }

    private var setupRunnerTabs: [TerminalSession] {
        runnerTabs.filter { SessionID.isSetup($0.id) }
    }

    private var configRunnerTabs: [TerminalSession] {
        runnerTabs
            .filter { !SessionID.isSetup($0.id) }
            .sorted { a, b in
                let configA = runConfiguration(for: a)
                let configB = runConfiguration(for: b)
                let autoA = configA?.autoStart ?? false
                let autoB = configB?.autoStart ?? false
                if autoA != autoB { return autoA }
                return (configA?.order ?? .max) < (configB?.order ?? .max)
            }
    }

    private var activeRunnerTabId: String? {
        terminalSessionManager.activeRunnerSessionId[worktreeId]
    }

    private var hasRunConfigurations: Bool {
        !(worktree.project?.profile?.runConfigurations.isEmpty ?? true)
    }

    private var isSetupGroupActive: Bool {
        guard let activeId = activeRunnerTabId else { return false }
        return SessionID.isSetup(activeId)
    }

    private var setupGroupState: SessionState {
        let tabs = setupRunnerTabs
        if tabs.contains(where: { $0.state == .failed }) { return .failed }
        if tabs.contains(where: { $0.state == .running }) { return .running }
        if tabs.allSatisfy({ $0.state == .succeeded }) && !tabs.isEmpty { return .succeeded }
        return .idle
    }

    private var setupGroupLabel: String {
        let total = setupRunnerTabs.count
        let done = setupRunnerTabs.filter { $0.state == .succeeded || $0.state == .failed }.count
        return "\(done)/\(total)"
    }

    private var hasSetupCommands: Bool {
        guard let commands = worktree.project?.profile?.setupCommands else { return false }
        return !commands.filter({ !$0.isEmpty }).isEmpty
    }

    var body: some View {
        if showRunnerPanel && (!runnerTabs.isEmpty || hasRunConfigurations) {
            runnerTerminalsView
        } else if !configRunnerTabs.isEmpty || hasRunConfigurations {
            runnerStatusBar
        }
    }

    // MARK: - Runner Terminals (Expanded)

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
                    if session.isSSH {
                        SSHTerminalRepresentable(session: session, isActive: isActiveRunner && isPaneFocused, theme: currentTheme)
                            .opacity(isActiveRunner ? 1 : 0)
                            .allowsHitTesting(isActiveRunner)
                    } else {
                        TerminalRepresentable(session: session, isActive: isActiveRunner && isPaneFocused, theme: currentTheme)
                            .opacity(isActiveRunner ? 1 : 0)
                            .allowsHitTesting(isActiveRunner)
                    }
                }

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
                    if !setupRunnerTabs.isEmpty {
                        setupGroupTab
                    }
                    ForEach(configRunnerTabs) { session in
                        runnerTab(session: session)
                    }
                }
            }

            Spacer()

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
                Button {
                    startRunners()
                } label: {
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
                Button {
                    restartAllRunners()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Restart All")

                Button {
                    stopAllRunners()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.subheadline)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Stop All")

                Button {
                    removeAllRunners()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.subheadline)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Close All Runners")
            }

            Button {
                showRunnerPanel = false
            } label: {
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
        let _ = terminalSessionManager.runnerStateVersion
        HStack(spacing: 4) {
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

            if !session.runAsCommand {
                if session.deferExecution {
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
                    Button {
                        terminalSessionManager.restartSession(id: session.id)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Restart")

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

    private func reorderRunnerConfig(droppedSessionId: String, targetSessionId: String) {
        guard let droppedSession = terminalSessionManager.session(for: droppedSessionId),
              let targetSession = terminalSessionManager.session(for: targetSessionId),
              let droppedConfig = runConfiguration(for: droppedSession),
              let targetConfig = runConfiguration(for: targetSession) else { return }
        guard droppedConfig.autoStart == targetConfig.autoStart else { return }

        let isAutoStart = droppedConfig.autoStart
        var groupConfigs = runConfigurations
            .filter { $0.autoStart == isAutoStart }
            .sorted { $0.order < $1.order }

        guard let fromIndex = groupConfigs.firstIndex(where: { $0.name == droppedConfig.name }),
              let toIndex = groupConfigs.firstIndex(where: { $0.name == targetConfig.name }) else { return }

        let moved = groupConfigs.remove(at: fromIndex)
        groupConfigs.insert(moved, at: toIndex)

        let baseOffset = isAutoStart ? 0 : 1000
        for (index, config) in groupConfigs.enumerated() {
            config.order = baseOffset + index
        }
    }

    // MARK: - Setup Group

    @ViewBuilder
    private var setupGroupTab: some View {
        let _ = terminalSessionManager.runnerStateVersion
        let allDone = setupRunnerTabs.allSatisfy({ $0.state == .succeeded || $0.state == .failed })
        HStack(spacing: 4) {
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
                Button {
                    confirmAndRunSetup()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Rerun Setup")

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

    // MARK: - Status Bar (Collapsed)

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

    // MARK: - Runner Actions

    func startRunners() {
        if let conflict = conflictingWorktree() {
            conflictingWorktreeName = conflict.name
            conflictingPorts = conflictingPortList()
            showRunnerConflictAlert = true
            return
        }
        launchRunners()
    }

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

    private func conflictingPortList() -> [Int] {
        guard let configs = worktree.project?.profile?.runConfigurations else { return [] }
        return configs.compactMap(\.port).sorted()
    }

    private func stopConflictingAndStartRunners() {
        guard let project = worktree.project else { return }
        for sibling in project.worktrees where sibling.path != worktreeId {
            for session in terminalSessionManager.runnerSessions(forWorktree: sibling.path) {
                terminalSessionManager.stopSession(id: session.id)
            }
            terminalSessionManager.removeRunnerSessions(forWorktree: sibling.path)
        }
        launchRunners()
    }

    func launchRunners() {
        ensureRunnerSessions()
        let defaultConfigs = runConfigurations.filter { $0.autoStart && !$0.command.isEmpty }
        for config in defaultConfigs {
            let sessionId = SessionID.runner(worktreeId: worktreeId, name: config.name)
            terminalSessionManager.startSession(id: sessionId)
        }
    }

    func ensureRunnerSessions() {
        for config in runConfigurations where !config.command.isEmpty {
            ensureRunnerSession(config: config)
        }
    }

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
        // Configure SSH if remote project
        if let project = worktree.project, project.isRemote, let sshConfig = project.sshConfig() {
            session.isSSH = true
            session.sshConnectionManager = sshConnectionManager
            session.sshConnectionConfig = sshConfig
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

    func runSetup() {
        let commands = (worktree.project?.profile?.setupCommands ?? []).filter { !$0.isEmpty }
        guard !commands.isEmpty else { return }
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
