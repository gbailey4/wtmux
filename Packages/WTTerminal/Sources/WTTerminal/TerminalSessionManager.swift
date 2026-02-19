import Foundation

// @unchecked Sendable: All access is gated by @MainActor. The @unchecked
// annotation is needed because @Observable's synthesised storage is not
// Sendable-aware, but @MainActor guarantees single-threaded access.
@MainActor @Observable
public final class TerminalSessionManager: @unchecked Sendable {
    public private(set) var sessions: [String: TerminalSession] = [:]
    public private(set) var activeSessionId: [String: String] = [:]
    private var portScanTimer: Timer?

    public init() {}

    public func createSession(
        id: String,
        title: String,
        worktreeId: String = "",
        workingDirectory: String,
        shellPath: String = Shell.default,
        initialCommand: String? = nil
    ) -> TerminalSession {
        if let existing = sessions[id] {
            return existing
        }
        let session = TerminalSession(
            id: id,
            title: title,
            worktreeId: worktreeId,
            workingDirectory: workingDirectory,
            shellPath: shellPath,
            initialCommand: initialCommand
        )
        sessions[id] = session
        return session
    }

    public func session(for id: String) -> TerminalSession? {
        sessions[id]
    }

    public func sessions(forWorktree worktreeId: String) -> [TerminalSession] {
        sessions.values
            .filter { $0.worktreeId == worktreeId }
            .sorted { $0.id < $1.id }
    }

    /// Returns the terminal (non-runner) session for a specific column, if any.
    public func terminalSession(forColumn columnId: String) -> TerminalSession? {
        sessions.values
            .first { $0.columnId == columnId && !SessionID.isRunner($0.id) }
    }

    /// Creates a terminal session for a column. Each column has exactly one terminal.
    public func createTerminal(forColumn columnId: String, worktreeId: String, workingDirectory: String, initialCommand: String? = nil) -> TerminalSession {
        let id = SessionID.tab(columnId: columnId, index: 1)
        let title = "Terminal"
        let session = createSession(
            id: id,
            title: title,
            worktreeId: worktreeId,
            workingDirectory: workingDirectory,
            initialCommand: initialCommand
        )
        session.columnId = columnId
        activeSessionId[columnId] = id
        return session
    }

    public func setActiveSession(columnId: String, sessionId: String) {
        activeSessionId[columnId] = sessionId
    }

    public func removeTerminal(sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        let key = session.columnId ?? session.worktreeId

        session.terminalView?.terminate()
        session.terminalView = nil
        sessions.removeValue(forKey: sessionId)

        if activeSessionId[key] == sessionId {
            activeSessionId.removeValue(forKey: key)
        }
    }

    public func removeSession(id: String) {
        sessions[id]?.terminalView?.terminate()
        sessions[id]?.terminalView = nil
        sessions.removeValue(forKey: id)
    }

    /// Terminates and removes all sessions (terminal + runners) for a worktree.
    public func terminateAllSessionsForWorktree(_ worktreeId: String) {
        // Collect columnIds before removal
        let columnIds = Set(sessions.values
            .filter { $0.worktreeId == worktreeId && !SessionID.isRunner($0.id) }
            .compactMap(\.columnId))

        let terminalIds = sessions.values
            .filter { $0.worktreeId == worktreeId && !SessionID.isRunner($0.id) }
            .map(\.id)
        for sessionId in terminalIds {
            removeTerminal(sessionId: sessionId)
        }
        removeRunnerSessions(forWorktree: worktreeId)

        // Clean up column-based state
        for columnId in columnIds {
            activeSessionId.removeValue(forKey: columnId)
        }
        // Also clean up legacy worktree-keyed state
        activeSessionId.removeValue(forKey: worktreeId)
    }

    /// Terminates and removes the terminal session for a specific column.
    public func terminateSessionsForColumn(_ columnId: String) {
        if let session = terminalSession(forColumn: columnId) {
            removeTerminal(sessionId: session.id)
        }
        activeSessionId.removeValue(forKey: columnId)
    }

    /// Moves a session from one column to another, preserving the terminal view.
    public func moveSession(sessionId: String, fromColumn: String, toColumn: String) {
        guard let session = sessions[sessionId] else { return }

        // Update session's column
        session.columnId = toColumn

        // Update active session in target
        activeSessionId[toColumn] = sessionId

        // Clear source
        if activeSessionId[fromColumn] == sessionId {
            activeSessionId.removeValue(forKey: fromColumn)
        }
    }

    /// Returns `true` if any session has an active process — either a runner
    /// in the `.running` state or a terminal with child processes.
    public func hasAnyRunningProcesses() -> Bool {
        for session in sessions.values {
            if SessionID.isRunner(session.id) {
                if session.state == .running { return true }
            } else {
                if session.terminalView?.hasChildProcesses() == true { return true }
            }
        }
        return false
    }

    public func removeAll() {
        stopPortScanning()
        for session in sessions.values {
            session.terminalView?.terminate()
            session.terminalView = nil
        }
        sessions.removeAll()
        activeSessionId.removeAll()
    }

    // MARK: - Runner Sessions

    /// Active runner tab per worktree (keyed by worktreeId).
    public private(set) var activeRunnerSessionId: [String: String] = [:]
    /// Incremented when runner state changes, so views can observe updates.
    public private(set) var runnerStateVersion: Int = 0

    public func createRunnerSession(
        id: String,
        title: String,
        worktreeId: String,
        workingDirectory: String,
        initialCommand: String,
        deferExecution: Bool = false
    ) -> TerminalSession {
        if let existing = sessions[id] {
            return existing
        }
        let session = TerminalSession(
            id: id,
            title: title,
            worktreeId: worktreeId,
            workingDirectory: workingDirectory,
            initialCommand: initialCommand,
            deferExecution: deferExecution
        )
        sessions[id] = session
        // Auto-select the first runner as active
        if activeRunnerSessionId[worktreeId] == nil {
            activeRunnerSessionId[worktreeId] = id
        }
        return session
    }

    /// Triggers a deferred command on an idle session.
    public func startSession(id: String) {
        guard let session = sessions[id],
              session.deferExecution,
              let view = session.terminalView,
              let command = session.initialCommand else { return }
        session.deferExecution = false
        session.state = .running
        view.sendCommand(command)
        runnerStateVersion += 1
        startPortScanning()
    }

    public func runnerSessions(forWorktree worktreeId: String) -> [TerminalSession] {
        sessions.values
            .filter { $0.worktreeId == worktreeId && SessionID.isRunner($0.id) }
            .sorted { $0.id < $1.id }
    }

    public func allRunnerSessions() -> [TerminalSession] {
        sessions.values
            .filter { SessionID.isRunner($0.id) }
            .sorted { $0.id < $1.id }
    }

    public func hasRunningSessions(forWorktree worktreeId: String) -> Bool {
        sessions.values.contains { $0.worktreeId == worktreeId && SessionID.isRunner($0.id) }
    }

    public func worktreeIdsWithRunners() -> Set<String> {
        Set(sessions.values.filter { SessionID.isRunner($0.id) && $0.isProcessRunning }.map(\.worktreeId))
    }

    public func removeRunnerSessions(forWorktree worktreeId: String) {
        let toRemove = runnerSessions(forWorktree: worktreeId)
        for session in toRemove {
            session.listeningPorts = []
            session.terminalView?.terminate()
            session.terminalView = nil
            sessions.removeValue(forKey: session.id)
        }
        activeRunnerSessionId.removeValue(forKey: worktreeId)
        stopPortScanningIfIdle()
    }

    public func setActiveRunnerSession(worktreeId: String, sessionId: String) {
        activeRunnerSessionId[worktreeId] = sessionId
    }

    /// Creates one setup runner session per command, each running non-interactively in its own tab.
    @discardableResult
    public func createSetupSessions(
        worktreeId: String,
        workingDirectory: String,
        commands: [String]
    ) -> [TerminalSession] {
        var results: [TerminalSession] = []
        for (index, command) in commands.enumerated() {
            let id = SessionID.setup(worktreeId: worktreeId, index: index)
            if let existing = sessions[id] {
                results.append(existing)
                continue
            }
            let session = TerminalSession(
                id: id,
                title: command,
                worktreeId: worktreeId,
                workingDirectory: workingDirectory,
                initialCommand: command
            )
            session.runAsCommand = true
            sessions[id] = session
            results.append(session)
        }
        // Auto-select the first setup session
        if let first = results.first {
            activeRunnerSessionId[worktreeId] = first.id
        }
        return results
    }

    /// Removes only setup sessions for a worktree, preserving config runner sessions.
    public func removeSetupSessions(forWorktree worktreeId: String) {
        let toRemove = sessions.values.filter { $0.worktreeId == worktreeId && SessionID.isSetup($0.id) }
        for session in toRemove {
            session.terminalView?.terminate()
            session.terminalView = nil
            sessions.removeValue(forKey: session.id)
        }
        // If the active runner was a setup session, clear it so a remaining runner can be selected
        if let activeId = activeRunnerSessionId[worktreeId], SessionID.isSetup(activeId) {
            let remaining = runnerSessions(forWorktree: worktreeId)
            activeRunnerSessionId[worktreeId] = remaining.first?.id
        }
    }

    /// Updates session state based on process exit code.
    public func handleProcessExit(sessionId: String, exitCode: Int32?) {
        guard let session = sessions[sessionId] else { return }
        session.state = (exitCode == 0) ? .succeeded : .failed
        session.listeningPorts = []
        runnerStateVersion += 1
        stopPortScanningIfIdle()
    }

    /// Sends Ctrl+C then re-sends the initial command after a short delay.
    public func restartSession(id: String) {
        guard let session = sessions[id],
              let view = session.terminalView,
              let command = session.initialCommand else { return }
        // Send Ctrl+C
        view.send([0x03])
        session.isProcessRunning = true
        runnerStateVersion += 1
        // Re-send command after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            view.sendCommand(command)
        }
    }

    /// Sends Ctrl+C to a runner session to stop it.
    public func stopSession(id: String) {
        guard let session = sessions[id],
              let view = session.terminalView else { return }
        view.send([0x03])
        session.isProcessRunning = false
        session.listeningPorts = []
        runnerStateVersion += 1
        stopPortScanningIfIdle()
    }

    // MARK: - Port Scanning

    private func startPortScanning() {
        guard portScanTimer == nil else { return }
        portScanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scanRunnerPorts()
            }
        }
    }

    private func stopPortScanning() {
        portScanTimer?.invalidate()
        portScanTimer = nil
    }

    /// Stops the timer when no runner sessions are in the `.running` state.
    private func stopPortScanningIfIdle() {
        let hasRunning = sessions.values.contains { SessionID.isRunner($0.id) && $0.state == .running }
        if !hasRunning {
            stopPortScanning()
        }
    }

    private func scanRunnerPorts() {
        var changed = false
        for session in sessions.values where SessionID.isRunner(session.id) && session.state == .running {
            guard let pid = session.terminalView?.process?.shellPid, pid > 0 else { continue }
            let ports = PortScanner.listeningPorts(forProcessTree: pid)
            if ports != session.listeningPorts {
                session.listeningPorts = ports
                changed = true
            }
        }
        if changed {
            runnerStateVersion += 1
        }
    }
}
