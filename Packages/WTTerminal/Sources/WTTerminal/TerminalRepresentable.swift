import SwiftUI
import WebKit

public struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSession

    public init(session: TerminalSession) {
        self.session = session
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = config.userContentController
        let coordinator = context.coordinator

        userContent.add(coordinator, name: "terminalReady")
        userContent.add(coordinator, name: "terminalInput")
        userContent.add(coordinator, name: "terminalResize")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        coordinator.webView = webView

        guard let htmlURL = Bundle.module.url(
            forResource: "terminal",
            withExtension: "html",
            subdirectory: "Resources"
        ) else {
            return webView
        }

        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // Terminal persists — no updates needed on re-render
    }

    public final class Coordinator: NSObject, WKScriptMessageHandler, @unchecked Sendable {
        let session: TerminalSession
        weak var webView: WKWebView?

        init(session: TerminalSession) {
            self.session = session
        }

        public func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "terminalReady":
                handleReady(message.body)
            case "terminalInput":
                handleInput(message.body)
            case "terminalResize":
                handleResize(message.body)
            default:
                break
            }
        }

        private func handleReady(_ body: Any) {
            guard let json = body as? String,
                  let data = json.data(using: .utf8),
                  let dims = try? JSONDecoder().decode(TerminalDimensions.self, from: data) else {
                return
            }

            let pty = PTYProcess()
            session.ptyProcess = pty

            pty.onOutput = { [weak self] data in
                guard let self else { return }
                let base64 = data.base64EncodedString()
                DispatchQueue.main.async { [weak self] in
                    self?.webView?.evaluateJavaScript("window.terminalWrite('\(base64)')")
                }
            }

            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"
            let envStrings = env.map { "\($0.key)=\($0.value)" }

            pty.start(
                executable: session.shellPath,
                environment: envStrings,
                currentDirectory: session.workingDirectory,
                cols: UInt16(dims.cols),
                rows: UInt16(dims.rows)
            )
        }

        private func handleInput(_ body: Any) {
            guard let base64 = body as? String,
                  let data = Data(base64Encoded: base64) else {
                return
            }
            session.ptyProcess?.write(data)
        }

        private func handleResize(_ body: Any) {
            guard let json = body as? String,
                  let data = json.data(using: .utf8),
                  let dims = try? JSONDecoder().decode(TerminalDimensions.self, from: data) else {
                return
            }
            session.ptyProcess?.resize(cols: UInt16(dims.cols), rows: UInt16(dims.rows))
        }
    }
}

private struct TerminalDimensions: Decodable {
    let cols: Int
    let rows: Int
}
