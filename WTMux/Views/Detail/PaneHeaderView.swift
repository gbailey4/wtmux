import os.log
import SwiftUI
import WTCore
import WTTerminal

private let dragLogger = Logger(subsystem: "com.wtmux", category: "PaneHeaderDrag")

struct PaneHeaderView: View {
    let pane: PaneState
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let worktree: Worktree?

    @State private var showClosePaneAlert = false

    private var hasRunningProcesses: Bool {
        guard let worktreeID = pane.worktreeID else { return false }
        let tabs = terminalSessionManager.orderedSessions(forWorktree: worktreeID)
        return tabs.contains { $0.terminalView?.hasChildProcesses() == true }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let worktree {
                if let projectName = worktree.project?.name {
                    Text(projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("/")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(worktree.branchName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Empty Pane")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                    if hasRunningProcesses {
                        showClosePaneAlert = true
                    } else {
                        paneManager.removePane(id: pane.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Pane")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
        .alert("Close Pane?", isPresented: $showClosePaneAlert) {
            Button("Close", role: .destructive) {
                paneManager.removePane(id: pane.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This pane has running terminal processes. Closing it will terminate them.")
        }
        .draggable(WorktreeReference(
            worktreeID: pane.worktreeID ?? "",
            sourcePaneID: pane.id.uuidString
        )) {
            HStack(spacing: 4) {
                if let worktree {
                    Text(worktree.branchName)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
