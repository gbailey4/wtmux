import AppKit
import SwiftTerm
import WTSSH

/// AppKit terminal view for SSH connections.
///
/// Mirrors SwiftTerm's iOS `SshTerminalView` pattern but for AppKit:
/// - Holds an `SSHShellSession` reference
/// - `TerminalViewDelegate.send()` → forwards bytes to SSH channel
/// - `TerminalViewDelegate.sizeChanged()` → sends WindowChangeRequest
/// - `SSHShellSession.onData` → calls `feed(byteArray:)` on the terminal
public class SSHTerminalView: TerminalView, @preconcurrency TerminalViewDelegate {
    private var shellSession: SSHShellSession?
    private let connectionManager: SSHConnectionManager
    private let config: SSHConnectionConfig
    private var started = false

    /// Called when the SSH shell session closes.
    public var onSessionClose: (@MainActor () -> Void)?

    public init(connectionManager: SSHConnectionManager, config: SSHConnectionConfig) {
        self.connectionManager = connectionManager
        self.config = config
        super.init(frame: .zero)
        self.terminalDelegate = self
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Starts the SSH shell session. Call after the view has a valid size.
    public func startSession() {
        guard !started else { return }
        started = true

        let cols = Int(getTerminal().cols)
        let rows = Int(getTerminal().rows)

        let session = SSHShellSession(connectionManager: connectionManager, config: config)

        session.onData = { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                let bytes = ArraySlice([UInt8](data))
                self.feed(byteArray: bytes)
            }
        }

        session.onClose = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.feed(text: "\r\n[SSH session closed]\r\n")
                self.onSessionClose?()
            }
        }

        self.shellSession = session

        Task {
            do {
                try await session.start(cols: cols, rows: rows)
            } catch {
                await MainActor.run {
                    self.feed(text: "\r\n[SSH connection failed: \(error.localizedDescription)]\r\n")
                }
            }
        }
    }

    /// Deferred start: wait for the view to be added to a window with valid size.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, frame.width > 0, frame.height > 0 {
            startSession()
        }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !started, window != nil, newSize.width > 0, newSize.height > 0 {
            startSession()
        }
    }

    /// Terminates the SSH shell session.
    public func terminate() {
        shellSession?.close()
        shellSession = nil
    }

    /// Whether the SSH session is still active.
    public var isSessionActive: Bool {
        shellSession?.isActive ?? false
    }

    // MARK: - TerminalViewDelegate

    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        shellSession?.send(Data(data))
    }

    public func scrolled(source: TerminalView, position: Double) {}

    public func setTerminalTitle(source: TerminalView, title: String) {}

    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        shellSession?.resize(cols: newCols, rows: newRows)
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    public func bell(source: TerminalView) {}

    public func clipboardCopy(source: TerminalView, content: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(content, forType: .string)
    }

    public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
