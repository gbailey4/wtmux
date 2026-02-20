import SwiftUI
import WTCore
import WTTerminal

struct MinimizedPaneStripView: View {
    let pane: WorktreePane
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
        guard let worktreeID = pane.worktreeID else { return nil }
        return claudeStatusManager.status(forPane: pane.id.uuidString, worktreePath: worktreeID)
    }

    private var hasRunningProcesses: Bool {
        let paneId = pane.id.uuidString
        if let session = terminalSessionManager.terminalSession(forPane: paneId),
           session.terminalView?.hasChildProcesses() == true {
            return true
        }
        if let worktreeID = pane.worktreeID {
            let runners = terminalSessionManager.sessions(forWorktree: worktreeID)
                .filter { SessionID.isRunner($0.id) && $0.state == .running }
            if !runners.isEmpty { return true }
        }
        return false
    }

    private var isRunning: Bool {
        guard let worktreeID = pane.worktreeID else { return false }
        let _ = terminalSessionManager.runnerStateVersion
        return terminalSessionManager.worktreeIdsWithRunners().contains(worktreeID)
    }

    private var runnerPorts: [UInt16] {
        guard let worktreeID = pane.worktreeID else { return [] }
        let _ = terminalSessionManager.runnerStateVersion
        return terminalSessionManager.runnerSessions(forWorktree: worktreeID)
            .flatMap { Array($0.listeningPorts) }
            .sorted()
    }

    var body: some View {
        Button {
            paneManager.restorePane(id: pane.id)
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

                if let label = pane.label, !label.isEmpty, pane.showLabel {
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help(label)
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
                    paneManager.restorePane(id: pane.id)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Restore Pane")

                Button {
                    if hasRunningProcesses {
                        showCloseAlert = true
                    } else {
                        paneManager.removePane(id: pane.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Pane")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(currentTheme.chromeBackground.toColor())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Close Pane?", isPresented: $showCloseAlert) {
            Button("Close", role: .destructive) {
                paneManager.removePane(id: pane.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This pane has running terminal processes. Closing it will terminate them.")
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

struct MinimizedPanesContainer: View {
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let findWorktree: (String) -> Worktree?

    var body: some View {
        let minimized = paneManager.minimizedPanes
        if !minimized.isEmpty {
            VStack(spacing: 1) {
                Divider()
                ForEach(minimized) { pane in
                    MinimizedPaneStripView(
                        pane: pane,
                        paneManager: paneManager,
                        terminalSessionManager: terminalSessionManager,
                        worktree: pane.worktreeID.flatMap { findWorktree($0) }
                    )
                }
            }
        }
    }
}
