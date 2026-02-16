import Foundation

// @unchecked Sendable: All access is gated by @MainActor. The @unchecked
// annotation is needed because @Observable's synthesised storage is not
// Sendable-aware, but @MainActor guarantees single-threaded access.
@MainActor @Observable
public final class TerminalSessionManager: @unchecked Sendable {
    public private(set) var sessions: [String: TerminalSession] = [:]
    public private(set) var activeSessionId: [String: String] = [:]
    public private(set) var tabOrder: [String: [String]] = [:]  // paneId (or worktreeId legacy) → [sessionId]
    private var tabCounters: [String: Int] = [:]
    private var portScanTimer: Timer?

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

    /// Returns terminal (non-runner) sessions for a worktree in display order (across all panes).
    public func orderedSessions(forWorktree worktreeId: String) -> [TerminalSession] {
        let tabs = sessions.values
            .filter { $0.worktreeId == worktreeId && !SessionID.isRunner($0.id) }
        // With pane-scoped sessions, tabOrder is keyed by paneId, so worktreeId lookup
        // won't find an order. Just sort by id for cleanup/query purposes.
        if let order = tabOrder[worktreeId] {
            let byId = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
            var ordered = order.compactMap { byId[$0] }
            let orderedIds = Set(order)
            let extras = tabs.filter { !orderedIds.contains($0.id) }.sorted { $0.id < $1.id }
            ordered.append(contentsOf: extras)
            return ordered
        }
        return tabs.sorted { $0.id < $1.id }
    }

    /// Returns terminal (non-runner) sessions for a specific pane in user-defined display order.
    public func orderedSessions(forPane paneId: String) -> [TerminalSession] {
        let tabs = sessions.values
            .filter { $0.paneId == paneId && !SessionID.isRunner($0.id) }
        if let order = tabOrder[paneId] {
            let byId = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
            var ordered = order.compactMap { byId[$0] }
            let orderedIds = Set(order)
            let extras = tabs.filter { !orderedIds.contains($0.id) }.sorted { $0.id < $1.id }
            ordered.append(contentsOf: extras)
            return ordered
        }
        return tabs.sorted { $0.id < $1.id }
    }

    /// Moves a terminal tab to a new index within a pane's tab order.
    public func moveTab(sessionId: String, toIndex index: Int, inPane paneId: String) {
        var order = tabOrder[paneId] ?? orderedSessions(forPane: paneId).map(\.id)
        guard let fromIndex = order.firstIndex(of: sessionId) else { return }
        order.remove(at: fromIndex)
        let clampedIndex = min(index, order.count)
        order.insert(sessionId, at: clampedIndex)
        tabOrder[paneId] = order
    }

    /// Moves a terminal tab to a new index within the worktree's tab order (legacy).
    public func moveTab(sessionId: String, toIndex index: Int, inWorktree worktreeId: String) {
        var order = tabOrder[worktreeId] ?? orderedSessions(forWorktree: worktreeId).map(\.id)
        guard let fromIndex = order.firstIndex(of: sessionId) else { return }
        order.remove(at: fromIndex)
        let clampedIndex = min(index, order.count)
        order.insert(sessionId, at: clampedIndex)
        tabOrder[worktreeId] = order
    }

    /// Renames a terminal session. Rejects empty strings and duplicate names within the same pane/worktree.
    @discardableResult
    public func renameTab(sessionId: String, to newTitle: String) -> Bool {
        guard !newTitle.isEmpty, let session = sessions[sessionId] else { return false }
        let siblings: [TerminalSession]
        if let paneId = session.paneId {
            siblings = orderedSessions(forPane: paneId)
        } else {
            siblings = orderedSessions(forWorktree: session.worktreeId)
        }
        if siblings.contains(where: { $0.id != sessionId && $0.title == newTitle }) { return false }
        session.title = newTitle
        return true
    }

    /// Creates a pane-scoped terminal tab.
    public func createTab(forPane paneId: String, worktreeId: String, workingDirectory: String, initialCommand: String? = nil) -> TerminalSession {
        let count = (tabCounters[paneId] ?? 0) + 1
        tabCounters[paneId] = count
        let id = SessionID.tab(paneId: paneId, index: count)
        let title = "Terminal \(count)"
        let session = createSession(
            id: id,
            title: title,
            worktreeId: worktreeId,
            workingDirectory: workingDirectory,
            initialCommand: initialCommand
        )
        session.paneId = paneId
        activeSessionId[paneId] = id
        if tabOrder[paneId] != nil {
            tabOrder[paneId]!.append(id)
        }
        return session
    }

    /// Creates a worktree-scoped terminal tab (legacy).
    public func createTab(forWorktree worktreeId: String, workingDirectory: String, initialCommand: String? = nil) -> TerminalSession {
        let count = (tabCounters[worktreeId] ?? 0) + 1
        tabCounters[worktreeId] = count
        let id = SessionID.tab(worktreeId: worktreeId, index: count)
        let title = "Terminal \(count)"
        let session = createSession(
            id: id,
            title: title,
            worktreeId: worktreeId,
            workingDirectory: workingDirectory,
            initialCommand: initialCommand
        )
        activeSessionId[worktreeId] = id
        if tabOrder[worktreeId] != nil {
            tabOrder[worktreeId]!.append(id)
        }
        return session
    }

    public func setActiveSession(worktreeId: String, sessionId: String) {
        activeSessionId[worktreeId] = sessionId
    }

    public func setActiveSession(paneId: String, sessionId: String) {
        activeSessionId[paneId] = sessionId
    }

    public func removeTab(sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        let key = session.paneId ?? session.worktreeId
        let wasActive = activeSessionId[key] == sessionId

        session.terminalView?.terminate()
        session.terminalView = nil
        session.sshTerminalView?.terminate()
        session.sshTerminalView = nil
        session.shellSession?.close()
        session.shellSession = nil
        sessions.removeValue(forKey: sessionId)
        tabOrder[key]?.removeAll { $0 == sessionId }

        if wasActive {
            if let paneId = session.paneId {
                let remaining = orderedSessions(forPane: paneId)
                activeSessionId[paneId] = remaining.last?.id
            } else {
                let remaining = orderedSessions(forWorktree: session.worktreeId)
                activeSessionId[session.worktreeId] = remaining.last?.id
            }
        }
    }

    public func removeSession(id: String) {
        sessions[id]?.terminalView?.terminate()
        sessions[id]?.terminalView = nil
        sessions[id]?.sshTerminalView?.terminate()
        sessions[id]?.sshTerminalView = nil
        sessions[id]?.shellSession?.close()
        sessions[id]?.shellSession = nil
        sessions.removeValue(forKey: id)
    }

    /// Terminates and removes all sessions (tabs + runners) for a worktree.
    public func terminateAllSessionsForWorktree(_ worktreeId: String) {
        // Collect paneIds before removal
        let paneIds = Set(sessions.values
            .filter { $0.worktreeId == worktreeId && !SessionID.isRunner($0.id) }
            .compactMap(\.paneId))

        let tabIds = sessions.values
            .filter { $0.worktreeId == worktreeId && !SessionID.isRunner($0.id) }
            .map(\.id)
        for sessionId in tabIds {
            removeTab(sessionId: sessionId)
        }
        removeRunnerSessions(forWorktree: worktreeId)

        // Clean up pane-based state
        for paneId in paneIds {
            activeSessionId.removeValue(forKey: paneId)
            tabOrder.removeValue(forKey: paneId)
            tabCounters.removeValue(forKey: paneId)
        }
        // Also clean up legacy worktree-keyed state
        activeSessionId.removeValue(forKey: worktreeId)
        tabOrder.removeValue(forKey: worktreeId)
        tabCounters.removeValue(forKey: worktreeId)
    }

    /// Terminates and removes all tab sessions for a specific pane.
    public func terminateSessionsForPane(_ paneId: String) {
        let tabIds = orderedSessions(forPane: paneId).map(\.id)
        for sessionId in tabIds {
            removeTab(sessionId: sessionId)
        }
        activeSessionId.removeValue(forKey: paneId)
        tabOrder.removeValue(forKey: paneId)
        tabCounters.removeValue(forKey: paneId)
    }

    /// Returns `true` if any session has an active process — either a runner
    /// in the `.running` state or a terminal tab with child processes.
    public func hasAnyRunningProcesses() -> Bool {
        for session in sessions.values {
            if SessionID.isRunner(session.id) {
                if session.state == .running { return true }
            } else if session.isSSH {
                if session.sshTerminalView?.isSessionActive == true { return true }
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
            session.sshTerminalView?.terminate()
            session.sshTerminalView = nil
            session.shellSession?.close()
            session.shellSession = nil
        }
        sessions.removeAll()
        activeSessionId.removeAll()
        tabCounters.removeAll()
        tabOrder.removeAll()
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
              let command = session.initialCommand else { return }

        if session.isSSH {
            guard session.sshTerminalView != nil else { return }
            session.deferExecution = false
            session.state = .running
            session.shellSession?.send(text: command + "\n")
            runnerStateVersion += 1
        } else {
            guard let view = session.terminalView else { return }
            session.deferExecution = false
            session.state = .running
            view.sendCommand(command)
            runnerStateVersion += 1
            startPortScanning()
        }
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
            session.sshTerminalView?.terminate()
            session.sshTerminalView = nil
            session.shellSession?.close()
            session.shellSession = nil
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
            session.sshTerminalView?.terminate()
            session.sshTerminalView = nil
            session.shellSession?.close()
            session.shellSession = nil
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
              let command = session.initialCommand else { return }

        if session.isSSH {
            // Send Ctrl+C via SSH
            session.shellSession?.send(Data([0x03]))
            session.isProcessRunning = true
            runnerStateVersion += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                session.shellSession?.send(text: command + "\n")
            }
        } else {
            guard let view = session.terminalView else { return }
            view.send([0x03])
            session.isProcessRunning = true
            runnerStateVersion += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                view.sendCommand(command)
            }
        }
    }

    /// Sends Ctrl+C to a runner session to stop it.
    public func stopSession(id: String) {
        guard let session = sessions[id] else { return }
        if session.isSSH {
            session.shellSession?.send(Data([0x03]))
        } else {
            session.terminalView?.send([0x03])
        }
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
            // Skip port scanning for SSH sessions — no local PID to inspect
            guard !session.isSSH else { continue }
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
