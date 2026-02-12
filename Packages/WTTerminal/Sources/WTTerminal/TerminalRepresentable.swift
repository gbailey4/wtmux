import Foundation
import SwiftUI
import SwiftTerm

public struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSession
    var isActive: Bool

    public init(session: TerminalSession, isActive: Bool = true) {
        self.session = session
        self.isActive = isActive
    }

    public func makeNSView(context: Context) -> DeferredStartTerminalView {
        if let existing = session.terminalView {
            return existing
        }

        let view = DeferredStartTerminalView(
            workingDirectory: session.workingDirectory,
            shellPath: session.shellPath
        )
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.font = font
        session.terminalView = view
        return view
    }

    public func updateNSView(_ nsView: DeferredStartTerminalView, context: Context) {
        if isActive {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

public class DeferredStartTerminalView: LocalProcessTerminalView {
    private var processStarted = false
    private let workingDirectory: String
    private let shellPath: String
    private var resizeTimer: Timer?

    public init(workingDirectory: String, shellPath: String) {
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        guard !processStarted, newSize.width > 0, newSize.height > 0 else { return }

        resizeTimer?.invalidate()
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startProcessIfNeeded()
            }
        }
    }

    // Force a full repaint when switching between normal/alt screen buffers
    // so TUI apps restore cleanly on exit.
    open override func bufferActivated(source: Terminal) {
        super.bufferActivated(source: source)
        setNeedsDisplay(bounds)
    }

    // MARK: - Kitty keyboard protocol filter

    /// Strips Kitty keyboard protocol sequences that SwiftTerm misinterprets.
    ///
    /// Claude Code sends CSI with private parameter prefixes (`<`, `>`, `?`) and
    /// final byte `u` for push/pop/query keyboard mode. SwiftTerm's CSI parser
    /// ignores the prefix and dispatches `u` as cursor restore, jumping the cursor
    /// to saved position (0,0).
    ///
    /// Pattern: `ESC [ [<>?] [0-9;]* u`
    open override func dataReceived(slice: ArraySlice<UInt8>) {
        let filtered = Self.filterKittyKeyboardSequences(slice)
        if filtered.count == slice.count {
            super.dataReceived(slice: slice)
        } else {
            filtered.withUnsafeBufferPointer { buffer in
                let arraySlice = Array(buffer)[...]
                super.dataReceived(slice: arraySlice)
            }
        }
    }

    static func filterKittyKeyboardSequences(_ input: ArraySlice<UInt8>) -> [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity(input.count)

        var i = input.startIndex
        let end = input.endIndex

        while i < end {
            // Look for ESC (0x1b)
            guard input[i] == 0x1b else {
                output.append(input[i])
                i += 1
                continue
            }

            // Need at least ESC [ <prefix> u = 4 bytes
            let remaining = end - i
            guard remaining >= 4, input[i + 1] == 0x5b else { // 0x5b = '['
                output.append(input[i])
                i += 1
                continue
            }

            let prefix = input[i + 2]
            // Check for private parameter prefix: < (0x3c), > (0x3e), ? (0x3f)
            guard prefix == 0x3c || prefix == 0x3e || prefix == 0x3f else {
                output.append(input[i])
                i += 1
                continue
            }

            // Scan past parameter bytes: digits (0x30-0x39) and semicolons (0x3b)
            var j = i + 3
            while j < end && ((input[j] >= 0x30 && input[j] <= 0x39) || input[j] == 0x3b) {
                j += 1
            }

            // Check for final byte 'u' (0x75)
            if j < end && input[j] == 0x75 {
                // Skip the entire Kitty keyboard sequence
                i = j + 1
            } else {
                // Not a Kitty sequence — emit the ESC and continue
                output.append(input[i])
                i += 1
            }
        }

        return output
    }

    // MARK: - Process lifecycle

    private func startProcessIfNeeded() {
        guard !processStarted else { return }
        processStarted = true

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        let envStrings = env.map { "\($0.key)=\($0.value)" }

        startProcess(
            executable: shellPath,
            args: [],
            environment: envStrings,
            execName: "-" + (shellPath as NSString).lastPathComponent,
            currentDirectory: workingDirectory
        )

        // Delayed SIGWINCH to force shell to redraw at correct dimensions
        if let pid = process?.shellPid, pid > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                kill(pid, SIGWINCH)
            }
        }
    }
}
