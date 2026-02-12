import Foundation

public final class LocalTransport: CommandTransport {
    public init() {}

    public func execute(_ command: String, in directory: String?) async throws -> CommandResult {
        try await execute(["/bin/sh", "-c", command], in: directory)
    }

    public func execute(_ arguments: [String], in directory: String?) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        if arguments.count > 1 {
            process.arguments = Array(arguments.dropFirst())
        }
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
