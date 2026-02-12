import Foundation
import WTTransport

public actor ProcessManager {
    private var processes: [String: ManagedProcess] = [:]
    private let portAllocator = PortAllocator()

    public init() {}

    public func startProcess(
        id: String,
        command: String,
        directory: String,
        port: Int? = nil,
        environment: [String: String] = [:]
    ) async throws -> ManagedProcess {
        if let existing = processes[id], existing.isRunning {
            await stopProcess(id: id)
        }

        let allocatedPort = port ?? portAllocator.allocate()
        var env = environment
        env["WT_EASY_PORT"] = String(allocatedPort)

        let process = ManagedProcess(
            id: id,
            command: command,
            directory: directory,
            port: allocatedPort,
            environment: env
        )

        processes[id] = process
        return process
    }

    public func stopProcess(id: String) async {
        guard let process = processes[id] else { return }
        process.terminate()
        processes.removeValue(forKey: id)
        portAllocator.release(process.port)
    }

    public func stopAll() async {
        for (id, _) in processes {
            await stopProcess(id: id)
        }
    }

    public func runningProcesses() -> [ManagedProcess] {
        Array(processes.values.filter(\.isRunning))
    }
}

public final class ManagedProcess: Sendable {
    public let id: String
    public let command: String
    public let directory: String
    public let port: Int
    public let environment: [String: String]

    nonisolated(unsafe) private var process: Process?
    nonisolated(unsafe) public private(set) var isRunning: Bool = false

    init(
        id: String,
        command: String,
        directory: String,
        port: Int,
        environment: [String: String]
    ) {
        self.id = id
        self.command = command
        self.directory = directory
        self.port = port
        self.environment = environment
    }

    func terminate() {
        process?.terminate()
        isRunning = false
    }
}

public final class PortAllocator: Sendable {
    nonisolated(unsafe) private var nextPort: Int = 3100
    nonisolated(unsafe) private var releasedPorts: [Int] = []

    public init() {}

    public func allocate() -> Int {
        if let port = releasedPorts.first {
            releasedPorts.removeFirst()
            return port
        }
        let port = nextPort
        nextPort += 1
        return port
    }

    public func release(_ port: Int) {
        releasedPorts.append(port)
    }
}
