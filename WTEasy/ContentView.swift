import SwiftUI
import SwiftData
import WTCore
import WTTerminal

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var selectedWorktreeID: String?
    @State private var showingAddProject = false
    @State private var showRightPanel = false
    @State private var showRunnerPanel = false
    @State private var changedFileCount: Int = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var terminalSessionManager = TerminalSessionManager()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                projects: projects,
                selectedWorktreeID: $selectedWorktreeID,
                showingAddProject: $showingAddProject,
                terminalSessionManager: terminalSessionManager
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let selectedWorktreeID,
               let worktree = findWorktree(id: selectedWorktreeID) {
                WorktreeDetailView(
                    worktree: worktree,
                    terminalSessionManager: terminalSessionManager,
                    showRightPanel: $showRightPanel,
                    showRunnerPanel: $showRunnerPanel,
                    changedFileCount: $changedFileCount
                )
            } else {
                ContentUnavailableView(
                    "No Worktree Selected",
                    systemImage: "terminal",
                    description: Text("Select a worktree from the sidebar or add a project to get started.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showRightPanel.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .overlay(alignment: .topTrailing) {
                            if changedFileCount > 0 {
                                Text("\(changedFileCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor, in: Capsule())
                                    .offset(x: 8, y: -8)
                            }
                        }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("Toggle Diff Panel (Cmd+Shift+D)")
            }
        }
        .sheet(isPresented: $showingAddProject) {
            AddProjectView()
        }
    }

    private func findWorktree(id: String) -> Worktree? {
        for project in projects {
            if let wt = project.worktrees.first(where: { $0.branchName == id }) {
                return wt
            }
        }
        return nil
    }
}
