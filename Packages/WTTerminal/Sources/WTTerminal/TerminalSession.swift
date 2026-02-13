import Foundation
import SwiftTerm

public enum SessionState: Sendable {
    case idle
    case running
    case succeeded
    case failed
}

public final class TerminalSession: Identifiable, @unchecked Sendable {
    public let id: String
    public let title: String
    public let worktreeId: String
    public let workingDirectory: String
    public let shellPath: String
    public var initialCommand: String?

    /// Lifecycle state for the session's process.
    public var state: SessionState

    /// Whether the runner command is currently active (not the shell itself).
    public var isProcessRunning: Bool {
        get { state == .running }
        set { state = newValue ? .running : .idle }
    }

    /// When true, the shell runs `initialCommand` via `-c` and exits instead of staying interactive.
    public var runAsCommand: Bool = false

    /// When true, the shell starts but `initialCommand` is not sent until explicitly triggered.
    public var deferExecution: Bool = false

    /// TCP ports detected in LISTEN state from the session's process tree.
    public var listeningPorts: Set<UInt16> = []

    /// Called when the process exits (for non-interactive / command mode sessions).
    /// Parameters: session ID, exit code.
    public var onProcessExit: (@MainActor (String, Int32?) -> Void)?

    nonisolated(unsafe) public var terminalView: DeferredStartTerminalView?

    public init(
        id: String,
        title: String,
        worktreeId: String = "",
        workingDirectory: String,
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        initialCommand: String? = nil,
        deferExecution: Bool = false
    ) {
        self.id = id
        self.title = title
        self.worktreeId = worktreeId
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath
        self.initialCommand = initialCommand
        self.deferExecution = deferExecution
        self.state = (initialCommand != nil && !deferExecution) ? .running : .idle
    }
}
