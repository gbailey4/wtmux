import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import WTTransport

/// `CommandTransport` implementation that executes commands over SSH.
public final class SSHTransport: CommandTransport {
    private let connectionManager: SSHConnectionManager
    private let config: SSHConnectionConfig
    private let eventLoopGroup: MultiThreadedEventLoopGroup

    public init(connectionManager: SSHConnectionManager, config: SSHConnectionConfig) {
        self.connectionManager = connectionManager
        self.config = config
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    public func execute(_ command: String, in directory: String?) async throws -> CommandResult {
        let fullCommand: String
        if let directory {
            // Shell-escape the directory and cd into it
            let escaped = shellEscape(directory)
            fullCommand = "cd \(escaped) && \(command)"
        } else {
            fullCommand = command
        }

        let connection = try await connectionManager.connection(for: config)
        let result = try await connection.executeCommand(fullCommand, eventLoopGroup: eventLoopGroup)

        return CommandResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    public func execute(_ arguments: [String], in directory: String?) async throws -> CommandResult {
        // SSH is inherently string-based — join arguments with shell escaping
        let command = arguments.map { shellEscape($0) }.joined(separator: " ")
        return try await execute(command, in: directory)
    }

    /// Shell-escapes a string for safe use in a remote shell command.
    private func shellEscape(_ string: String) -> String {
        // If the string is simple (alphanumeric, slashes, dots, hyphens, underscores), leave it unquoted
        let simplePattern = #"^[a-zA-Z0-9/.@_:=-]+$"#
        if string.range(of: simplePattern, options: .regularExpression) != nil {
            return string
        }
        // Otherwise, wrap in single quotes and escape any embedded single quotes
        return "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
