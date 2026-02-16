import Foundation

/// Manages an interactive PTY channel over SSH for terminal use.
///
/// Adapted from SwiftTerm's iOS `SshTerminalView` pattern:
/// - Holds a `ShellChannelHandle` for bidirectional I/O
/// - `send(Data)` → writes to SSH channel
/// - `resize(cols:rows:)` → sends WindowChangeRequest
/// - `onData` callback → feeds bytes to terminal view
/// - `onClose` callback → notifies when channel closes
public final class SSHShellSession: @unchecked Sendable {
    private let connectionManager: SSHConnectionManager
    private let config: SSHConnectionConfig
    private var handle: ShellChannelHandle?

    /// Called when data is received from the remote shell.
    public var onData: (@Sendable (Data) -> Void)?

    /// Called when the shell session closes.
    public var onClose: (@Sendable () -> Void)?

    public init(connectionManager: SSHConnectionManager, config: SSHConnectionConfig) {
        self.connectionManager = connectionManager
        self.config = config
    }

    /// Opens an interactive shell with a PTY.
    public func start(cols: Int, rows: Int) async throws {
        let connection = try await connectionManager.connection(for: config)

        let onData = self.onData
        let onClose = self.onClose

        let channelHandle = try await connection.openShellChannel(
            cols: cols,
            rows: rows,
            onData: { data in
                onData?(data)
            },
            onClose: {
                onClose?()
            }
        )

        self.handle = channelHandle
    }

    /// Sends raw bytes to the remote shell.
    public func send(_ data: Data) {
        handle?.send(data)
    }

    /// Sends a string to the remote shell.
    public func send(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        send(data)
    }

    /// Notifies the remote side of a terminal resize.
    public func resize(cols: Int, rows: Int) {
        handle?.resize(cols: cols, rows: rows)
    }

    /// Closes the shell session.
    public func close() {
        handle?.close()
        handle = nil
    }

    /// Whether the shell channel is still open.
    public var isActive: Bool {
        handle?.isActive ?? false
    }
}
