import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandTransport: Sendable {
    func execute(_ command: String, in directory: String?) async throws -> CommandResult
    func execute(_ arguments: [String], in directory: String?) async throws -> CommandResult
}

extension CommandTransport {
    public func execute(_ command: String) async throws -> CommandResult {
        try await execute(command, in: nil)
    }

    public func execute(_ arguments: [String]) async throws -> CommandResult {
        try await execute(arguments, in: nil)
    }
}
