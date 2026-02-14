import SwiftUI
import WTCore
import WTTerminal

struct PaneContentView: View {
    let pane: PaneState
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let findWorktree: (String) -> Worktree?

    private var isFocused: Bool {
        paneManager.focusedPaneID == pane.id
    }

    private var worktree: Worktree? {
        guard let id = pane.worktreeID else { return nil }
        return findWorktree(id)
    }

    private var showRightPanel: Binding<Bool> {
        Binding(
            get: { pane.showRightPanel },
            set: { pane.showRightPanel = $0 }
        )
    }

    private var showRunnerPanel: Binding<Bool> {
        Binding(
            get: { pane.showRunnerPanel },
            set: { pane.showRunnerPanel = $0 }
        )
    }

    private var changedFileCount: Binding<Int> {
        Binding(
            get: { pane.changedFileCount },
            set: { pane.changedFileCount = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if paneManager.panes.count > 1 {
                PaneHeaderView(pane: pane, paneManager: paneManager, terminalSessionManager: terminalSessionManager, worktree: worktree)
                Divider()
            }

            if let worktree {
                WorktreeDetailView(
                    worktree: worktree,
                    terminalSessionManager: terminalSessionManager,
                    showRightPanel: showRightPanel,
                    showRunnerPanel: showRunnerPanel,
                    changedFileCount: changedFileCount,
                    isPaneFocused: isFocused
                )
            } else {
                emptyPanePlaceholder
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.accentColor, lineWidth: isFocused && paneManager.panes.count > 1 ? 2 : 0)
        )
        .overlay(
            DropIndicatorView(zone: pane.dropZone)
        )
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
    }
}
