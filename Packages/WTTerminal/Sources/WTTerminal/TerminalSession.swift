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
        initialCommand: String? = nil
    ) {
        self.id = id
        self.title = title
        self.worktreeId = worktreeId
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath
        self.initialCommand = initialCommand
        self.state = initialCommand != nil ? .running : .idle
    }
}
