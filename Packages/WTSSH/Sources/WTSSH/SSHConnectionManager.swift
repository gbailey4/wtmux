import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Manages pooled SSH connections. One NIOSSH connection per unique host+port+user.
public actor SSHConnectionManager {
    private var connections: [String: SSHConnection] = [:]
    private let eventLoopGroup: MultiThreadedEventLoopGroup

    public init() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    /// Returns an existing connection or creates a new one for the given config.
    public func connection(for config: SSHConnectionConfig) async throws -> SSHConnection {
        let key = config.poolKey

        if let existing = connections[key], existing.isActive {
            return existing
        }

        // Remove stale connection
        connections.removeValue(forKey: key)

        let conn = try await SSHConnection.connect(config: config, eventLoopGroup: eventLoopGroup)
        connections[key] = conn
        return conn
    }

    /// Tests connectivity. Returns nil on success, or an error message on failure.
    public func testConnection(_ config: SSHConnectionConfig) async -> String? {
        do {
            let conn = try await connection(for: config)
            // Run a trivial command to verify the channel works
            let result = try await conn.executeCommand("echo ok", eventLoopGroup: eventLoopGroup)
            if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                return nil
            }
            return "Connection established but command execution failed"
        } catch {
            return error.localizedDescription
        }
    }

    /// Disconnects a specific connection.
    public func disconnect(for config: SSHConnectionConfig) async {
        let key = config.poolKey
        if let conn = connections.removeValue(forKey: key) {
            await conn.close()
        }
    }

    /// Disconnects all connections.
    public func disconnectAll() async {
        for conn in connections.values {
            await conn.close()
        }
        connections.removeAll()
    }
}

/// Represents a single SSH connection backed by NIOSSH.
public final class SSHConnection: @unchecked Sendable {
    private let channel: Channel
    let multiplexer: NIOSSHHandler

    init(channel: Channel, multiplexer: NIOSSHHandler) {
        self.channel = channel
        self.multiplexer = multiplexer
    }

    /// Whether the underlying channel is still active.
    var isActive: Bool {
        channel.isActive
    }

    /// Establishes a new SSH connection.
    static func connect(config: SSHConnectionConfig, eventLoopGroup: EventLoopGroup) async throws -> SSHConnection {
        let authDelegate: NIOSSHClientUserAuthenticationDelegate
        switch config.authMethod {
        case .keyFile(let path, let passphrase):
            authDelegate = KeyFileAuthDelegate(username: config.username, keyPath: path, passphrase: passphrase)
        }

        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: authDelegate,
                            serverAuthDelegate: AcceptAllHostKeysDelegate()
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    ),
                ])
            }
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(.seconds(30))

        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: config.host, port: config.port).get()
        } catch {
            throw SSHError.connectionFailed(error.localizedDescription)
        }

        // Wait for authentication to complete by trying a child channel
        let handler = try await channel.pipeline.handler(type: NIOSSHHandler.self).get()

        return SSHConnection(channel: channel, multiplexer: handler)
    }

    /// Executes a command and returns stdout, stderr, and exit code.
    func executeCommand(_ command: String, eventLoopGroup: EventLoopGroup) async throws -> CommandExecResult {
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandExecResult, Error>) in
            // All NIO channel operations must happen on the event loop thread
            channel.eventLoop.execute {
                let promise = self.channel.eventLoop.makePromise(of: Channel.self)

                let handler = ExecChannelHandler(command: command, continuation: continuation)

                self.multiplexer.createChannel(promise) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(SSHError.channelFailed("unexpected channel type"))
                    }
                    return childChannel.pipeline.addHandlers([handler])
                }

                promise.futureResult.whenFailure { error in
                    continuation.resume(throwing: SSHError.channelFailed(error.localizedDescription))
                }
            }
        }
        return result
    }

    /// Opens an interactive shell channel with a PTY for terminal use.
    func openShellChannel(
        cols: Int,
        rows: Int,
        onData: @escaping @Sendable (Data) -> Void,
        onClose: @escaping @Sendable () -> Void
    ) async throws -> ShellChannelHandle {
        let handle = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellChannelHandle, Error>) in
            // All NIO channel operations must happen on the event loop thread
            channel.eventLoop.execute {
                let promise = self.channel.eventLoop.makePromise(of: Channel.self)

                let handler = ShellChannelHandler(
                    cols: cols,
                    rows: rows,
                    onData: onData,
                    onClose: onClose,
                    continuation: continuation
                )

                self.multiplexer.createChannel(promise) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(SSHError.channelFailed("unexpected channel type"))
                    }
                    return childChannel.pipeline.addHandlers([handler])
                }

                promise.futureResult.whenFailure { error in
                    continuation.resume(throwing: SSHError.channelFailed(error.localizedDescription))
                }
            }
        }
        return handle
    }

    /// Closes the connection.
    func close() async {
        try? await channel.close().get()
    }
}

// MARK: - Host Key Delegate (accept all — trust-on-first-use deferred)

final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        // Phase 1: accept all host keys. TOFU verification is a future milestone.
        validationCompletePromise.succeed(())
    }
}

// MARK: - Command Execution Result

struct CommandExecResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

// MARK: - Exec Channel Handler

private final class ExecChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    private let command: String
    private var continuation: CheckedContinuation<CommandExecResult, Error>?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var exitCode: Int32 = -1

    init(command: String, continuation: CheckedContinuation<CommandExecResult, Error>) {
        self.command = command
        self.continuation = continuation
    }

    func handlerAdded(context: ChannelHandlerContext) {
        // Request exec
        let execRequest = SSHChannelRequestEvent.ExecRequest(
            command: command,
            wantReply: true
        )
        context.triggerUserOutboundEvent(execRequest, promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        switch channelData.type {
        case .channel:
            if case .byteBuffer(var buffer) = channelData.data,
               let bytes = buffer.readBytes(length: buffer.readableBytes) {
                stdoutBuffer.append(contentsOf: bytes)
            }
        case .stdErr:
            if case .byteBuffer(var buffer) = channelData.data,
               let bytes = buffer.readBytes(length: buffer.readableBytes) {
                stderrBuffer.append(contentsOf: bytes)
            }
        default:
            break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? SSHChannelRequestEvent.ExitStatus {
            exitCode = Int32(event.exitStatus)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        let result = CommandExecResult(
            stdout: String(data: stdoutBuffer, encoding: .utf8) ?? "",
            stderr: String(data: stderrBuffer, encoding: .utf8) ?? "",
            exitCode: exitCode
        )
        continuation?.resume(returning: result)
        continuation = nil
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        context.close(promise: nil)
    }
}

// MARK: - Shell Channel Handler + Handle

/// A handle to an open interactive shell channel, used for sending data and resizing.
public final class ShellChannelHandle: @unchecked Sendable {
    private let channel: Channel

    init(channel: Channel) {
        self.channel = channel
    }

    /// Sends raw bytes to the remote shell.
    public func send(_ data: Data) {
        guard channel.isActive else { return }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        channel.writeAndFlush(channelData, promise: nil)
    }

    /// Notifies the remote side of a terminal resize.
    public func resize(cols: Int, rows: Int) {
        guard channel.isActive else { return }
        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        channel.triggerUserOutboundEvent(request, promise: nil)
    }

    /// Closes the shell channel.
    public func close() {
        guard channel.isActive else { return }
        channel.close(promise: nil)
    }

    /// Whether the channel is still open.
    public var isActive: Bool {
        channel.isActive
    }
}

private final class ShellChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    private let cols: Int
    private let rows: Int
    private let onData: @Sendable (Data) -> Void
    private let onClose: @Sendable () -> Void
    private var continuation: CheckedContinuation<ShellChannelHandle, Error>?

    init(
        cols: Int,
        rows: Int,
        onData: @escaping @Sendable (Data) -> Void,
        onClose: @escaping @Sendable () -> Void,
        continuation: CheckedContinuation<ShellChannelHandle, Error>
    ) {
        self.cols = cols
        self.rows = rows
        self.onData = onData
        self.onClose = onClose
        self.continuation = continuation
    }

    func handlerAdded(context: ChannelHandlerContext) {
        // Request PTY
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        context.triggerUserOutboundEvent(ptyRequest, promise: nil)

        // Request shell
        let shellRequest = SSHChannelRequestEvent.ShellRequest(wantReply: true)
        context.triggerUserOutboundEvent(shellRequest, promise: nil)

        // Succeed the continuation with a handle
        let handle = ShellChannelHandle(channel: context.channel)
        continuation?.resume(returning: handle)
        continuation = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        if case .channel = channelData.type {
            if case .byteBuffer(var buffer) = channelData.data,
               let bytes = buffer.readBytes(length: buffer.readableBytes) {
                onData(Data(bytes))
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        onClose()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        context.close(promise: nil)
    }
}
