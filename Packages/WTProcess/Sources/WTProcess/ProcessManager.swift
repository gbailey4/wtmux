import Foundation
import WTTransport

/// Describes a managed process entry. Immutable snapshot returned from the actor.
public struct ManagedProcess: Sendable {
    public let id: String
    public let command: String
    public let directory: String
    public let port: Int
    public let environment: [String: String]
    public let isRunning: Bool
}

public actor ProcessManager {
    private var entries: [String: ManagedProcess] = [:]

    // MARK: - Port Allocation

    private var nextPort: Int = 3100
    private var releasedPorts: [Int] = []

    public init() {}

    private func allocatePort() -> Int {
        if let port = releasedPorts.first {
            releasedPorts.removeFirst()
            return port
        }
        let port = nextPort
        nextPort += 1
        return port
    }

    private func releasePort(_ port: Int) {
        releasedPorts.append(port)
    }

    // MARK: - Process Management

    public func startProcess(
        id: String,
        command: String,
        directory: String,
        port: Int? = nil,
        environment: [String: String] = [:]
    ) async -> ManagedProcess {
        if let existing = entries[id], existing.isRunning {
            await stopProcess(id: id)
        }

        let allocatedPort = port ?? allocatePort()
        var env = environment
        env["WTMUX_PORT"] = String(allocatedPort)

        let entry = ManagedProcess(
            id: id,
            command: command,
            directory: directory,
            port: allocatedPort,
            environment: env,
            isRunning: true
        )

        entries[id] = entry
        return entry
    }

    public func stopProcess(id: String) async {
        guard let entry = entries[id] else { return }
        entries.removeValue(forKey: id)
        releasePort(entry.port)
    }

    public func stopAll() async {
        for (id, _) in entries {
            await stopProcess(id: id)
        }
    }

    public func runningProcesses() -> [ManagedProcess] {
        Array(entries.values.filter(\.isRunning))
    }
}
