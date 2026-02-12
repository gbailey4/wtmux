import Foundation

public final class TerminalSession: Identifiable, @unchecked Sendable {
    public let id: String
    public let title: String
    public let worktreeId: String
    public let workingDirectory: String
    public let shellPath: String

    nonisolated(unsafe) public var ptyProcess: PTYProcess?

    public init(
        id: String,
        title: String,
        worktreeId: String = "",
        workingDirectory: String,
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    ) {
        self.id = id
        self.title = title
        self.worktreeId = worktreeId
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath
    }
}
