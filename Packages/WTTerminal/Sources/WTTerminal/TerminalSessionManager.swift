import Foundation

@Observable
public final class TerminalSessionManager: @unchecked Sendable {
    public private(set) var sessions: [String: TerminalSession] = [:]

    public init() {}

    public func createSession(
        id: String,
        title: String,
        workingDirectory: String,
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    ) -> TerminalSession {
        if let existing = sessions[id] {
            return existing
        }
        let session = TerminalSession(
            id: id,
            title: title,
            workingDirectory: workingDirectory,
            shellPath: shellPath
        )
        sessions[id] = session
        return session
    }

    public func session(for id: String) -> TerminalSession? {
        sessions[id]
    }

    public func removeSession(id: String) {
        sessions[id]?.ptyProcess?.stop()
        sessions.removeValue(forKey: id)
    }

    public func removeAll() {
        for session in sessions.values {
            session.ptyProcess?.stop()
        }
        sessions.removeAll()
    }
}
