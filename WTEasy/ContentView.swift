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
    @State private var terminalSessionManager = TerminalSessionManager()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                projects: projects,
                selectedWorktreeID: $selectedWorktreeID,
                showingAddProject: $showingAddProject
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let selectedWorktreeID,
               let worktree = findWorktree(id: selectedWorktreeID) {
                WorktreeDetailView(
                    worktree: worktree,
                    terminalSessionManager: terminalSessionManager,
                    showRightPanel: $showRightPanel
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
