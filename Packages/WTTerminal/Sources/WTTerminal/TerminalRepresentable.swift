import Foundation
import SwiftUI
import SwiftTerm

enum KittyCommand: Equatable {
    case push(level: Int)
    case pop(count: Int)
    case query
}

public struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSession
    var isActive: Bool
    var theme: TerminalTheme

    public init(session: TerminalSession, isActive: Bool = true, theme: TerminalTheme = TerminalThemes.defaultTheme) {
        self.session = session
        self.isActive = isActive
        self.theme = theme
    }

    public func makeNSView(context: Context) -> DeferredStartTerminalView {
        if let existing = session.terminalView {
            return existing
        }

        let view = DeferredStartTerminalView(
            workingDirectory: session.workingDirectory,
            shellPath: session.shellPath,
            initialCommand: session.initialCommand,
            deferExecution: session.deferExecution
        )
        view.columnId = session.columnId
        view.runAsCommand = session.runAsCommand
        if let onExit = session.onProcessExit {
            let sessionId = session.id
            view.onProcessExit = { exitCode in
                onExit(sessionId, exitCode)
            }
        }
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.font = font
        applyTheme(theme, to: view)
        session.terminalView = view
        return view
    }

    public func updateNSView(_ nsView: DeferredStartTerminalView, context: Context) {
        applyTheme(theme, to: nsView)
        if isActive {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    private func applyTheme(_ theme: TerminalTheme, to view: DeferredStartTerminalView) {
        view.nativeBackgroundColor = theme.background.toNSColor()
        view.nativeForegroundColor = theme.foreground.toNSColor()
        view.caretColor = theme.cursor.toNSColor()
        view.selectedTextBackgroundColor = theme.selection.toNSColor()
        view.installColors(theme.ansiColors.map { $0.toSwiftTermColor() })
    }
}

public class DeferredStartTerminalView: LocalProcessTerminalView {
    private var processStarted = false
    private let workingDirectory: String
    private let shellPath: String
    private let initialCommand: String?
    private var resizeTimer: Timer?
    private var deferExecution: Bool

    /// The column ID this terminal belongs to, injected as `WTMUX_COLUMN_ID` env var.
    public var columnId: String?

    /// When true, starts shell with `-c command` instead of interactive mode.
    public var runAsCommand: Bool = false

    /// Called when the process exits (only fires for non-interactive / command mode).
    public var onProcessExit: (@MainActor (Int32?) -> Void)?

    /// Stack of Kitty keyboard enhancement levels pushed by the hosted application.
    private var kittyKeyboardStack: [Int] = []

    /// Current Kitty keyboard enhancement level (top of stack, or 0 if empty).
    var kittyKeyboardLevel: Int { kittyKeyboardStack.last ?? 0 }

    /// Local event monitor for intercepting key events when Kitty mode is active.
    private var keyEventMonitor: Any?

    public init(workingDirectory: String, shellPath: String, initialCommand: String? = nil, deferExecution: Bool = false) {
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath
        self.initialCommand = initialCommand
        self.deferExecution = deferExecution
        super.init(frame: .zero)

        let scrollback = max(500, min(50_000, UserDefaults.standard.object(forKey: "terminalScrollbackLines") as? Int ?? 5_000))
        getTerminal().changeHistorySize(scrollback)

        // Install key event monitor eagerly — viewDidMoveToWindow may not fire
        // reliably in SwiftUI's NSViewRepresentable lifecycle. The firstResponder
        // guard in handleKeyEventForKitty prevents stealing events from other views.
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEventForKitty(event) ?? event
        }
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
        processReceivedData(slice)
    }

    private func processReceivedData(_ slice: ArraySlice<UInt8>) {
        let (filtered, commands) = Self.filterKittyKeyboardSequences(slice)

        for command in commands {
            switch command {
            case .push(let level):
                kittyKeyboardStack.append(level)
            case .pop(let count):
                let removeCount = min(count, kittyKeyboardStack.count)
                if removeCount > 0 {
                    kittyKeyboardStack.removeLast(removeCount)
                }
            case .query:
                send(txt: "\u{1b}[?\(kittyKeyboardLevel)u")
            }
        }

        if filtered.count == slice.count {
            super.dataReceived(slice: slice)
        } else if !filtered.isEmpty {
            filtered.withUnsafeBufferPointer { buffer in
                let arraySlice = Array(buffer)[...]
                super.dataReceived(slice: arraySlice)
            }
        }
    }

    static func filterKittyKeyboardSequences(_ input: ArraySlice<UInt8>) -> (filtered: [UInt8], commands: [KittyCommand]) {
        var output = [UInt8]()
        var commands = [KittyCommand]()
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
                // Parse first numeric parameter
                var firstParam = 0
                var hasParam = false
                for k in (i + 3)..<j {
                    let byte = input[k]
                    if byte >= 0x30 && byte <= 0x39 {
                        firstParam = firstParam * 10 + Int(byte - 0x30)
                        hasParam = true
                    } else {
                        break // semicolon — stop at first param
                    }
                }

                switch prefix {
                case 0x3e: // > push
                    commands.append(.push(level: firstParam))
                case 0x3c: // < pop
                    commands.append(.pop(count: hasParam ? firstParam : 1))
                case 0x3f: // ? query
                    commands.append(.query)
                default:
                    break
                }

                i = j + 1
            } else {
                // Not a Kitty sequence — emit the ESC and continue
                output.append(input[i])
                i += 1
            }
        }

        return (filtered: output, commands: commands)
    }

    // MARK: - Kitty keyboard input encoding

    /// Install/remove an NSEvent local monitor to intercept key events when Kitty
    /// keyboard mode is active. The monitor runs before NSWindow dispatches to the
    /// responder chain, letting us encode modified keys as Kitty CSI sequences
    /// before SwiftTerm's non-overridable `keyDown` processes them.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Clean up monitors when removed from the window hierarchy.
        if window == nil {
            if let monitor = keyEventMonitor {
                NSEvent.removeMonitor(monitor)
                keyEventMonitor = nil
            }
        }
    }

    /// Encode a key event per the Kitty keyboard protocol when active.
    /// Returns `nil` to consume the event, or the original event to pass through.
    private func handleKeyEventForKitty(_ event: NSEvent) -> NSEvent? {
        guard window?.firstResponder === self else { return event }

        // Shift+Enter → synthesize Option+Enter so it follows the same path
        // (either our Kitty CSI u encoder if active, or SwiftTerm's native
        // Option meta-key handling which sends ESC CR).
        if event.keyCode == 36
            && event.modifierFlags.contains(.shift)
            && !event.modifierFlags.contains(.command) {
            let optionFlags = event.modifierFlags
                .subtracting(.shift)
                .union(.option)
            return NSEvent.keyEvent(
                with: .keyDown,
                location: event.locationInWindow,
                modifierFlags: optionFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        guard kittyKeyboardLevel > 0 else { return event }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = !flags.subtracting([.capsLock, .numericPad, .function]).isEmpty
        guard hasModifier else { return event }

        // Don't intercept Command combos (except Cmd+Backspace) — let system handle copy/paste/etc.
        if flags.contains(.command) && event.keyCode != 51 {
            return event
        }

        // Map hardware key codes to Unicode codepoints
        let codepoint: Int
        switch event.keyCode {
        case 36: codepoint = 13   // Return
        case 48: codepoint = 9    // Tab
        case 51: codepoint = 127  // Backspace
        case 53: codepoint = 27   // Escape
        default:
            guard let chars = event.charactersIgnoringModifiers,
                  let scalar = chars.unicodeScalars.first,
                  scalar.value >= 32 && scalar.value < 127 else {
                return event
            }
            codepoint = Int(scalar.value)
        }

        // Kitty modifier encoding: 1 + (shift?1:0) + (alt?2:0) + (ctrl?4:0) + (super?8:0)
        var mods = 1
        if flags.contains(.shift) { mods += 1 }
        if flags.contains(.option) { mods += 2 }
        if flags.contains(.control) { mods += 4 }
        if flags.contains(.command) { mods += 8 }

        guard mods > 1 else { return event }

        send(txt: "\u{1b}[\(codepoint);\(mods)u")
        return nil // consume the event
    }

    /// Fallback for Command+Backspace when Kitty mode is inactive.
    /// Sends Ctrl+U (delete to beginning of line) since SwiftTerm's non-overridable
    /// `doCommand(by:)` doesn't handle the `deleteToBeginningOfLine:` selector.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Shift+Enter → LF (newline without submit) when Kitty mode is inactive
        if event.keyCode == 36
            && event.modifierFlags.contains(.shift)
            && !event.modifierFlags.contains(.command)
            && kittyKeyboardLevel == 0 {
            send(txt: "\n")
            return true
        }
        // Cmd+Backspace → Ctrl+U (delete to beginning of line)
        if event.keyCode == 51 && event.modifierFlags.contains(.command) && kittyKeyboardLevel == 0 {
            send(txt: "\u{15}") // Ctrl+U
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Child process detection

    /// Returns `true` when the shell has active child processes (e.g. ssh, node, python).
    public func hasChildProcesses() -> Bool {
        guard let pid = process?.shellPid, pid > 0 else { return false }
        var childPids = [pid_t](repeating: 0, count: 256)
        let bufferSize = Int32(MemoryLayout<pid_t>.size * childPids.count)
        let count = proc_listchildpids(pid, &childPids, bufferSize)
        return count > 0
    }

    // MARK: - Process lifecycle

    public override func processTerminated(_ source: SwiftTerm.LocalProcess, exitCode: Int32?) {
        onProcessExit?(exitCode)
        super.processTerminated(source, exitCode: exitCode)
    }

    /// Environment variables that should not propagate from the app to child terminals.
    /// `CLAUDECODE` — Claude Code sets this to detect nested sessions; inheriting it
    /// causes all terminals to reject `claude` with "cannot launch inside another session".
    private static let strippedEnvVars: Set<String> = ["CLAUDECODE"]

    private func startProcessIfNeeded() {
        guard !processStarted else { return }
        processStarted = true
        kittyKeyboardStack = []

        var env = ProcessInfo.processInfo.environment
        for key in Self.strippedEnvVars { env.removeValue(forKey: key) }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if let columnId { env["WTMUX_COLUMN_ID"] = columnId }
        let envStrings = env.map { "\($0.key)=\($0.value)" }

        let useCommandMode = runAsCommand && initialCommand != nil
        let args: [String] = useCommandMode ? ["-c", initialCommand!] : []

        startProcess(
            executable: shellPath,
            args: args,
            environment: envStrings,
            execName: useCommandMode ? (shellPath as NSString).lastPathComponent : "-" + (shellPath as NSString).lastPathComponent,
            currentDirectory: workingDirectory
        )

        // Delayed SIGWINCH to force shell to redraw at correct dimensions
        if let pid = process?.shellPid, pid > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                kill(pid, SIGWINCH)
            }
        }

        // Send initial command after shell has time to initialize (interactive mode only)
        if !useCommandMode, !deferExecution, let command = initialCommand, !command.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.sendCommand(command)
            }
        }
    }

    /// Sends a command string to the PTY followed by a newline.
    public func sendCommand(_ command: String) {
        send(txt: command + "\n")
    }
}
