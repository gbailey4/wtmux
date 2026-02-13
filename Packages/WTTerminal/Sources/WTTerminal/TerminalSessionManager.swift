import Foundation

@MainActor @Observable
public final class TerminalSessionManager: @unchecked Sendable {
    public private(set) var sessions: [String: TerminalSession] = [:]
    public private(set) var activeSessionId: [String: String] = [:]
    private var tabCounters: [String: Int] = [:]

    public init() {}

    public func createSession(
        id: String,
        title: String,
        worktreeId: String = "",
        workingDirectory: String,
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
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

    public func createTab(forWorktree worktreeId: String, workingDirectory: String, initialCommand: String? = nil) -> TerminalSession {
        let count = (tabCounters[worktreeId] ?? 0) + 1
        tabCounters[worktreeId] = count
        let id = "tab-\(worktreeId)-\(count)"
        let title = "Terminal \(count)"
        let session = createSession(
            id: id,
            title: title,
            worktreeId: worktreeId,
            workingDirectory: workingDirectory,
            initialCommand: initialCommand
        )
        activeSessionId[worktreeId] = id
        return session
    }

    public func setActiveSession(worktreeId: String, sessionId: String) {
        activeSessionId[worktreeId] = sessionId
    }

    public func removeTab(sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        let worktreeId = session.worktreeId
        let wasActive = activeSessionId[worktreeId] == sessionId

        session.terminalView?.terminate()
        session.terminalView = nil
        sessions.removeValue(forKey: sessionId)

        if wasActive {
            let remaining = sessions(forWorktree: worktreeId)
            activeSessionId[worktreeId] = remaining.last?.id
        }
    }

    public func removeSession(id: String) {
        sessions[id]?.terminalView?.terminate()
        sessions[id]?.terminalView = nil
        sessions.removeValue(forKey: id)
    }

    public func removeAll() {
        for session in sessions.values {
            session.terminalView?.terminate()
            session.terminalView = nil
        }
        sessions.removeAll()
        activeSessionId.removeAll()
        tabCounters.removeAll()
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
    }

    public func runnerSessions(forWorktree worktreeId: String) -> [TerminalSession] {
        sessions.values
            .filter { $0.worktreeId == worktreeId && $0.id.hasPrefix("runner-") }
            .sorted { $0.id < $1.id }
    }

    public func allRunnerSessions() -> [TerminalSession] {
        sessions.values
            .filter { $0.id.hasPrefix("runner-") }
            .sorted { $0.id < $1.id }
    }

    public func hasRunningSessions(forWorktree worktreeId: String) -> Bool {
        sessions.values.contains { $0.worktreeId == worktreeId && $0.id.hasPrefix("runner-") }
    }

    public func worktreeIdsWithRunners() -> Set<String> {
        Set(sessions.values.filter { $0.id.hasPrefix("runner-") && $0.isProcessRunning }.map(\.worktreeId))
    }

    public func removeRunnerSessions(forWorktree worktreeId: String) {
        let toRemove = runnerSessions(forWorktree: worktreeId)
        for session in toRemove {
            session.terminalView?.terminate()
            session.terminalView = nil
            sessions.removeValue(forKey: session.id)
        }
        activeRunnerSessionId.removeValue(forKey: worktreeId)
    }

    public func setActiveRunnerSession(worktreeId: String, sessionId: String) {
        activeRunnerSessionId[worktreeId] = sessionId
    }

    /// Creates a setup runner session that runs a command non-interactively.
    public func createSetupSession(
        worktreeId: String,
        workingDirectory: String,
        command: String
    ) -> TerminalSession {
        let id = "runner-\(worktreeId)-setup"
        if let existing = sessions[id] {
            return existing
        }
        let session = TerminalSession(
            id: id,
            title: "Setup",
            worktreeId: worktreeId,
            workingDirectory: workingDirectory,
            initialCommand: command
        )
        session.runAsCommand = true
        sessions[id] = session
        activeRunnerSessionId[worktreeId] = id
        return session
    }

    /// Updates session state based on process exit code.
    public func handleProcessExit(sessionId: String, exitCode: Int32?) {
        guard let session = sessions[sessionId] else { return }
        session.state = (exitCode == 0) ? .succeeded : .failed
        runnerStateVersion += 1
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
        runnerStateVersion += 1
    }
}
