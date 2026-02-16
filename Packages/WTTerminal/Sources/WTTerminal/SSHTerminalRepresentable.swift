import Foundation
import SwiftUI
import SwiftTerm
import WTSSH

/// NSViewRepresentable for SSH terminal sessions (parallel to `TerminalRepresentable`).
public struct SSHTerminalRepresentable: NSViewRepresentable {
    let session: TerminalSession
    var isActive: Bool
    var theme: TerminalTheme

    public init(session: TerminalSession, isActive: Bool = true, theme: TerminalTheme = TerminalThemes.defaultTheme) {
        self.session = session
        self.isActive = isActive
        self.theme = theme
    }

    public func makeNSView(context: Context) -> SSHTerminalView {
        if let existing = session.sshTerminalView {
            return existing
        }

        guard let connectionManager = session.sshConnectionManager,
              let config = session.sshConnectionConfig else {
            fatalError("SSH session requires connectionManager and config")
        }

        let view = SSHTerminalView(connectionManager: connectionManager, config: config)

        if let onClose = session.onProcessExit {
            let sessionId = session.id
            view.onSessionClose = {
                onClose(sessionId, 0)
            }
        }

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.font = font
        applyTheme(theme, to: view)
        session.sshTerminalView = view

        // Send initial command after connection is established
        if let command = session.initialCommand, !command.isEmpty, !session.deferExecution {
            Task {
                // Wait for the session to connect
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    if view.isSessionActive {
                        view.feed(text: "") // ensure connection is up
                        session.shellSession?.send(text: command + "\n")
                    }
                }
            }
        }

        return view
    }

    public func updateNSView(_ nsView: SSHTerminalView, context: Context) {
        applyTheme(theme, to: nsView)
        if isActive {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    private func applyTheme(_ theme: TerminalTheme, to view: SSHTerminalView) {
        view.nativeBackgroundColor = theme.background.toNSColor()
        view.nativeForegroundColor = theme.foreground.toNSColor()
        view.caretColor = theme.cursor.toNSColor()
        view.selectedTextBackgroundColor = theme.selection.toNSColor()
        view.installColors(theme.ansiColors.map { $0.toSwiftTermColor() })
    }
}
