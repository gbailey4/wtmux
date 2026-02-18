import SwiftUI
import WTCore
import WTTerminal

struct PaneContentView: View {
    let pane: PaneState
    let column: WorktreeColumn
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let findWorktree: (String) -> Worktree?

    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @Environment(ThemeManager.self) private var themeManager

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

    private var isFocused: Bool {
        paneManager.focusedPaneID == pane.id
    }

    private var worktree: Worktree? {
        guard let id = column.worktreeID else { return nil }
        return findWorktree(id)
    }

    private var showRightPanel: Binding<Bool> {
        Binding(
            get: { pane.showRightPanel },
            set: { pane.showRightPanel = $0 }
        )
    }

    private var changedFileCount: Binding<Int> {
        Binding(
            get: { pane.changedFileCount },
            set: { pane.changedFileCount = $0 }
        )
    }

    private var showFocusBorder: Bool {
        paneManager.columns.count > 1 || column.panes.count > 1
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeaderView(
                pane: pane,
                column: column,
                paneManager: paneManager,
                terminalSessionManager: terminalSessionManager,
                worktree: worktree,
                isActive: isFocused
            )
            Divider()

            if let worktree {
                WorktreeDetailView(
                    worktree: worktree,
                    paneId: pane.id.uuidString,
                    terminalSessionManager: terminalSessionManager,
                    paneManager: paneManager,
                    showRightPanel: showRightPanel,
                    changedFileCount: changedFileCount,
                    isPaneFocused: isFocused
                )
            } else {
                emptyPanePlaceholder
            }
        }
        .overlay(alignment: .top) {
            if isFocused && showFocusBorder {
                Color.accentColor.frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            paneManager.focusedPaneID = pane.id
        }
    }

    @ViewBuilder
    private var emptyPanePlaceholder: some View {
        ContentUnavailableView(
            "No Worktree",
            systemImage: "rectangle.split.2x1",
            description: Text("Select a worktree from the sidebar to display it in this pane.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(currentTheme.background.toColor())
    }
}
