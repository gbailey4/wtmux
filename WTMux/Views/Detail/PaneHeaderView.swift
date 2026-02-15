import os.log
import SwiftUI
import WTCore
import WTTerminal

private let dragLogger = Logger(subsystem: "com.wtmux", category: "PaneHeaderDrag")

struct PaneHeaderView: View {
    let pane: PaneState
    let column: WorktreeColumn
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let worktree: Worktree?
    var showCloseButton: Bool = true

    @State private var showClosePaneAlert = false

    private var hasRunningProcesses: Bool {
        let tabs = terminalSessionManager.orderedSessions(forPane: pane.id.uuidString)
        return tabs.contains { $0.terminalView?.hasChildProcesses() == true }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let worktree {
                if let project = worktree.project {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(projectColor(for: project))
                        .frame(width: 3, height: 12)
                    Image(systemName: project.resolvedIconName)
                        .foregroundStyle(projectColor(for: project))
                        .font(.caption)
                    Text(project.name)
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

            if showCloseButton {
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
        .contextMenu {
            Button("New Terminal in Split") {
                paneManager.splitSameWorktree()
            }

            Divider()

            Button("Move to New Window") {
                paneManager.moveColumnToNewWindow(columnID: column.id)
            }
            .disabled(paneManager.focusedWindow?.columns.count ?? 0 <= 1)

            if paneManager.windows.count > 1 {
                Menu("Move to Window\u{2026}") {
                    ForEach(paneManager.windows.filter({ $0.id != paneManager.focusedWindowID })) { window in
                        Button(window.name) {
                            paneManager.moveColumnToWindow(columnID: column.id, targetWindowID: window.id)
                        }
                    }
                }
            }
        }
        .draggable(WorktreeReference(
            worktreeID: column.worktreeID ?? "",
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
