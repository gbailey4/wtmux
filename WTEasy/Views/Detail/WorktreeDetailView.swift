import SwiftUI
import WTCore
import WTTerminal
import WTDiff
import WTGit
import WTTransport

struct WorktreeDetailView: View {
    let worktree: Worktree
    let terminalSessionManager: TerminalSessionManager
    @Binding var showRightPanel: Bool

    @State private var runnerTerminalSessions: [TerminalSession] = []
    @State private var selectedRunnerTab: String?
    @State private var diffFiles: [DiffFile] = []
    @State private var selectedDiffFile: DiffFile?

    private var worktreeId: String { worktree.branchName }

    private var terminalTabs: [TerminalSession] {
        terminalSessionManager.sessions(forWorktree: worktreeId)
    }

    private var activeTabId: String? {
        terminalSessionManager.activeSessionId[worktreeId]
    }

    private var allTabSessions: [TerminalSession] {
        terminalSessionManager.sessions.values
            .filter { !$0.worktreeId.isEmpty }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Center: Main terminal tabs + runner terminals
            VStack(spacing: 0) {
                // Main terminal with tabs
                tabbedTerminalView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom: Runner terminal tabs
                if !runnerTerminalSessions.isEmpty {
                    Divider()
                    runnerTerminalsView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 150, maxHeight: 300)
                }
            }

            // Right panel: Diff viewer
            if showRightPanel {
                Divider()
                diffPanelView
                    .frame(width: 400)
            }
        }
        .task(id: worktreeId) {
            ensureFirstTab()
            if showRightPanel {
                await loadDiff()
            }
        }
        .onChange(of: showRightPanel) { _, visible in
            if visible {
                Task { await loadDiff() }
            }
        }
    }

    private func ensureFirstTab() {
        if terminalSessionManager.sessions(forWorktree: worktreeId).isEmpty {
            _ = terminalSessionManager.createTab(
                forWorktree: worktreeId,
                workingDirectory: worktree.path
            )
        }
    }

    // MARK: - Tabbed Terminal

    @ViewBuilder
    private var tabbedTerminalView: some View {
        VStack(spacing: 0) {
            terminalTabBar
            ZStack {
                // All tab sessions across ALL worktrees live here so
                // WKWebViews (and their PTY output streams) survive
                // worktree switches.  Only the active tab is visible.
                ForEach(allTabSessions) { session in
                    let active = session.id == activeTabId
                    TerminalRepresentable(session: session, isActive: active)
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                }
            }
        }
    }

    @ViewBuilder
    private var terminalTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(terminalTabs) { session in
                        terminalTab(session: session)
                    }
                }
            }

            Spacer()

            Button {
                _ = terminalSessionManager.createTab(
                    forWorktree: worktreeId,
                    workingDirectory: worktree.path
                )
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func terminalTab(session: TerminalSession) -> some View {
        HStack(spacing: 4) {
            Button {
                terminalSessionManager.setActiveSession(worktreeId: worktreeId, sessionId: session.id)
            } label: {
                Text(session.title)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            if terminalTabs.count > 1 {
                Button {
                    terminalSessionManager.removeTab(sessionId: session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(session.id == activeTabId ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    // MARK: - Runner Terminals

    @ViewBuilder
    private var runnerTerminalsView: some View {
        VStack(spacing: 0) {
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(runnerTerminalSessions) { session in
                        Button {
                            selectedRunnerTab = session.id
                        } label: {
                            Text(session.title)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedRunnerTab == session.id
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(.bar)

            // Selected runner terminal
            if let tabID = selectedRunnerTab,
               let session = runnerTerminalSessions.first(where: { $0.id == tabID }) {
                TerminalRepresentable(session: session)
            }
        }
    }

    // MARK: - Diff Panel

    @ViewBuilder
    private var diffPanelView: some View {
        VStack(spacing: 0) {
            // File list header
            HStack {
                Text("Changes")
                    .font(.headline)
                Spacer()
                Text("\(diffFiles.count) files")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(8)
            .background(.bar)

            Divider()

            if diffFiles.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("No differences from \(worktree.baseBranch)")
                )
            } else {
                HSplitView {
                    // File list
                    List(diffFiles, selection: Binding(
                        get: { selectedDiffFile?.id },
                        set: { id in selectedDiffFile = diffFiles.first(where: { $0.id == id }) }
                    )) { file in
                        Text(file.displayPath)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .tag(file.id)
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 150)

                    // Diff content
                    if let file = selectedDiffFile {
                        InlineDiffView(file: file)
                    } else {
                        ContentUnavailableView(
                            "Select a File",
                            systemImage: "doc.text",
                            description: Text("Choose a file to view its diff")
                        )
                    }
                }
            }
        }
    }

    private func loadDiff() async {
        guard let project = worktree.project else { return }
        let transport = LocalTransport()
        let git = GitService(transport: transport, repoPath: project.repoPath)
        do {
            let diffOutput = try await git.diff(
                baseBranch: worktree.baseBranch,
                branch: worktree.branchName
            )
            let parser = DiffParser()
            diffFiles = parser.parse(diffOutput)
            selectedDiffFile = diffFiles.first
        } catch {
            diffFiles = []
        }
    }
}
