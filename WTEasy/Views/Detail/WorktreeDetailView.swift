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

    var body: some View {
        HStack(spacing: 0) {
            // Center: Main terminal + runner terminals
            VStack(spacing: 0) {
                // Main Claude Code terminal
                mainTerminalView
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
        .task(id: worktree.branchName) {
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

    @ViewBuilder
    private var mainTerminalView: some View {
        let session = terminalSessionManager.createSession(
            id: "cc-\(worktree.branchName)",
            title: "Claude Code - \(worktree.branchName)",
            workingDirectory: worktree.path
        )
        TerminalRepresentable(session: session)
    }

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
