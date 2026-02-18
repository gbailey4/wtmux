import SwiftUI
import WTCore
import WTGit
import WTTerminal
import WTTransport

struct WorktreeDetailView: View {
    let worktree: Worktree
    let columnId: String
    let terminalSessionManager: TerminalSessionManager
    let paneManager: SplitPaneManager
    @Binding var showRightPanel: Bool
    @Binding var changedFileCount: Int
    var isColumnFocused: Bool = true

    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @Environment(ThemeManager.self) private var themeManager

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

    private var worktreeId: String { worktree.path }

    private var terminalTabs: [TerminalSession] {
        terminalSessionManager.orderedSessions(forPane: columnId)
    }

    private var activeTabId: String? {
        terminalSessionManager.activeSessionId[columnId]
    }

    private var columnUUID: UUID {
        UUID(uuidString: columnId) ?? UUID()
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
                    columnID: columnUUID,
                    changedFileCount: $changedFileCount
                )
                .frame(width: 400)
            }
        }
        .task(id: "\(worktreeId)-\(columnId)") {
            changedFileCount = 0
            ensureFirstTab()
            let git = GitService(transport: LocalTransport(), repoPath: worktree.path)
            if let files = try? await git.status() {
                changedFileCount = files.count
            }
        }
    }

    private func ensureFirstTab() {
        guard terminalSessionManager.orderedSessions(forPane: columnId).isEmpty else { return }

        let startCommand: String? = {
            guard let cmd = worktree.project?.profile?.terminalStartCommand, !cmd.isEmpty else { return nil }
            return cmd
        }()

        _ = terminalSessionManager.createTab(
            forPane: columnId,
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            initialCommand: startCommand
        )
    }

    // MARK: - Terminal Content

    @ViewBuilder
    private var terminalContentView: some View {
        ZStack {
            ForEach(terminalTabs) { session in
                let isActiveTab = session.id == activeTabId
                TerminalRepresentable(session: session, isActive: isActiveTab && isColumnFocused, theme: currentTheme)
                    .padding(.leading, 8)
                    .opacity(isActiveTab ? 1 : 0)
                    .allowsHitTesting(isActiveTab)
            }
            if terminalTabs.isEmpty {
                ContentUnavailableView {
                    Label("No Terminal", systemImage: "terminal")
                } description: {
                    Text("Open a new terminal to get started.")
                } actions: {
                    Button("New Terminal") {
                        ensureFirstTab()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(currentTheme.background.toColor())
    }
}
