import SwiftUI
import SwiftTerm
import AppKit

public struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSession

    public init(session: TerminalSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = DeferredStartTerminalView(frame: .zero)
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let shell = session.shellPath
        let env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        let shellName = "-" + (shell as NSString).lastPathComponent
        let session = self.session

        terminalView.deferProcessStart { [weak terminalView] in
            guard let terminalView else { return }
            terminalView.startProcess(
                executable: shell,
                args: [],
                environment: env,
                execName: shellName,
                currentDirectory: session.workingDirectory
            )
            session.localProcess = terminalView.process

            // After layout fully settles, force the shell to re-query terminal
            // dimensions and redraw. This fixes rendering corruption from
            // intermediate sizes during SwiftUI layout animations.
            let pid = terminalView.process.shellPid
            if pid > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    kill(pid, SIGWINCH)
                }
            }
        }

        return terminalView
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Terminal persists — no updates needed on re-render
    }
}

/// Defers shell process startup until the view's layout has fully settled,
/// ensuring the PTY gets correct initial terminal dimensions.
///
/// SwiftUI layout can span multiple run loop iterations (e.g. NavigationSplitView
/// animations). Each setFrameSize call resets a 50ms debounce timer. The process
/// starts only after no setFrameSize has been called for 50ms, meaning layout
/// has stabilized and the frame reflects the actual visible area.
private final class DeferredStartTerminalView: LocalProcessTerminalView {
    private var pendingStart: (() -> Void)?

    func deferProcessStart(_ start: @escaping () -> Void) {
        pendingStart = start
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard pendingStart != nil, newSize.width > 0, newSize.height > 0 else { return }

        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(fireStart),
            object: nil
        )
        perform(#selector(fireStart), with: nil, afterDelay: 0.05)
    }

    @objc private func fireStart() {
        guard let start = pendingStart else { return }
        pendingStart = nil
        start()
    }
}
