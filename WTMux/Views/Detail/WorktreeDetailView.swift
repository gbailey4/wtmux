import SwiftUI
import WTCore
import WTGit
import WTTerminal
import WTTransport

struct WorktreeDetailView: View {
    let worktree: Worktree
    let paneId: String
    let terminalSessionManager: TerminalSessionManager
    let paneManager: SplitPaneManager
    @Binding var showRightPanel: Bool
    @Binding var changedFileCount: Int
    var isPaneFocused: Bool = true

    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @Environment(ThemeManager.self) private var themeManager

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

    private var worktreeId: String { worktree.path }

    private var terminalSession: TerminalSession? {
        terminalSessionManager.terminalSession(forPane: paneId)
    }

    private var paneUUID: UUID {
        UUID(uuidString: paneId) ?? UUID()
    }

    var body: some View {
        HStack(spacing: 0) {
            terminalContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showRightPanel {
                Divider()
                ChangesPanel(
                    worktree: worktree,
                    paneManager: paneManager,
                    paneID: paneUUID,
                    changedFileCount: $changedFileCount
                )
                .frame(width: 400)
            }
        }
        .task(id: "\(worktreeId)-\(paneId)") {
            changedFileCount = 0
            ensureTerminal()
            let git = GitService(transport: LocalTransport(), repoPath: worktree.path)
            if let files = try? await git.status() {
                changedFileCount = files.count
            }
        }
    }

    private func ensureTerminal() {
        guard terminalSessionManager.terminalSession(forPane: paneId) == nil else { return }

        let startCommand: String? = {
            guard let cmd = worktree.project?.profile?.terminalStartCommand, !cmd.isEmpty else { return nil }
            return cmd
        }()

        _ = terminalSessionManager.createTerminal(
            forPane: paneId,
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            initialCommand: startCommand
        )
    }

    // MARK: - Terminal Content

    @ViewBuilder
    private var terminalContentView: some View {
        if let session = terminalSession {
            TerminalRepresentable(session: session, isActive: isPaneFocused, theme: currentTheme)
                .padding(.leading, 8)
                .background(currentTheme.background.toColor())
        } else {
            ContentUnavailableView {
                Label("No Terminal", systemImage: "terminal")
            } description: {
                Text("Open a new terminal to get started.")
            } actions: {
                Button("New Terminal") {
                    ensureTerminal()
                }
                .buttonStyle(.borderedProminent)
            }
            .background(currentTheme.background.toColor())
        }
    }
}
