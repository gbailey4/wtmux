import Foundation

public final class TerminalSession: Identifiable, @unchecked Sendable {
    public let id: String
    public let title: String
    public let workingDirectory: String
    public let shellPath: String

    nonisolated(unsafe) public var ptyProcess: PTYProcess?

    public init(
        id: String,
        title: String,
        workingDirectory: String,
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath
    }
}
