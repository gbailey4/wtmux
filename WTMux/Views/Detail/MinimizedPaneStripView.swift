import SwiftUI
import WTCore
import WTTerminal

struct MinimizedPaneStripView: View {
    let column: WorktreeColumn
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let worktree: Worktree?

    @Environment(ClaudeStatusManager.self) private var claudeStatusManager
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @Environment(ThemeManager.self) private var themeManager
    @State private var showCloseAlert = false

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

    private var claudeStatus: ClaudeCodeStatus? {
        guard let worktreeID = column.worktreeID else { return nil }
        return claudeStatusManager.status(forColumn: column.id.uuidString, worktreePath: worktreeID)
    }

    private var hasRunningProcesses: Bool {
        let columnId = column.id.uuidString
        if let session = terminalSessionManager.terminalSession(forColumn: columnId),
           session.terminalView?.hasChildProcesses() == true {
            return true
        }
        if let worktreeID = column.worktreeID {
            let runners = terminalSessionManager.sessions(forWorktree: worktreeID)
                .filter { SessionID.isRunner($0.id) && $0.state == .running }
            if !runners.isEmpty { return true }
        }
        return false
    }

    private var isRunning: Bool {
        guard let worktreeID = column.worktreeID else { return false }
        let _ = terminalSessionManager.runnerStateVersion
        return terminalSessionManager.worktreeIdsWithRunners().contains(worktreeID)
    }

    private var runnerPorts: [UInt16] {
        guard let worktreeID = column.worktreeID else { return [] }
        let _ = terminalSessionManager.runnerStateVersion
        return terminalSessionManager.runnerSessions(forWorktree: worktreeID)
            .flatMap { Array($0.listeningPorts) }
            .sorted()
    }

    var body: some View {
        Button {
            paneManager.restoreColumn(id: column.id)
        } label: {
            HStack(spacing: 6) {
                if let worktree {
                    if let project = worktree.project {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(projectColor(for: project))
                            .frame(width: 3, height: 12)
                    }

                    Text(worktree.branchName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Empty")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let status = claudeStatus {
                    claudeStatusIcon(status)
                }

                if isRunning {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                        .help("Runners active")
                }

                if !runnerPorts.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "network")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(runnerPorts.map(String.init).joined(separator: ","))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button {
                    paneManager.restoreColumn(id: column.id)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Restore Column")

                Button {
                    if hasRunningProcesses {
                        showCloseAlert = true
                    } else {
                        paneManager.removeColumn(id: column.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Column")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(currentTheme.chromeBackground.toColor())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Close Column?", isPresented: $showCloseAlert) {
            Button("Close", role: .destructive) {
                paneManager.removeColumn(id: column.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This column has running terminal processes. Closing it will terminate them.")
        }
    }

    @ViewBuilder
    private func claudeStatusIcon(_ status: ClaudeCodeStatus) -> some View {
        switch status {
        case .idle:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
        case .thinking:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.purple)
                .symbolEffect(.pulse)
        case .working:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .needsAttention:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)
        }
    }
}

struct MinimizedColumnsContainer: View {
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let findWorktree: (String) -> Worktree?

    var body: some View {
        let minimized = paneManager.minimizedColumns
        if !minimized.isEmpty {
            VStack(spacing: 1) {
                Divider()
                ForEach(minimized) { column in
                    MinimizedPaneStripView(
                        column: column,
                        paneManager: paneManager,
                        terminalSessionManager: terminalSessionManager,
                        worktree: column.worktreeID.flatMap { findWorktree($0) }
                    )
                }
            }
        }
    }
}
