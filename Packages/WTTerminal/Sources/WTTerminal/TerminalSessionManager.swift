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
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    ) -> TerminalSession {
        if let existing = sessions[id] {
            return existing
        }
        let session = TerminalSession(
            id: id,
            title: title,
            worktreeId: worktreeId,
            workingDirectory: workingDirectory,
            shellPath: shellPath
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

    public func createTab(forWorktree worktreeId: String, workingDirectory: String) -> TerminalSession {
        let count = (tabCounters[worktreeId] ?? 0) + 1
        tabCounters[worktreeId] = count
        let id = "tab-\(worktreeId)-\(count)"
        let title = "Terminal \(count)"
        let session = createSession(
            id: id,
            title: title,
            worktreeId: worktreeId,
            workingDirectory: workingDirectory
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
}
