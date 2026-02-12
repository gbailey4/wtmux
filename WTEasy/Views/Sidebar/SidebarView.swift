import SwiftUI
import SwiftData
import WTCore
import WTTerminal

struct SidebarView: View {
    let projects: [Project]
    @Binding var selectedWorktreeID: String?
    @Binding var showingAddProject: Bool
    let terminalSessionManager: TerminalSessionManager

    @Environment(\.modelContext) private var modelContext
    @State private var worktreeTargetProject: Project?
    @State private var editingProject: Project?

    private var runningWorktreeIds: Set<String> {
        terminalSessionManager.worktreeIdsWithRunners()
    }

    var body: some View {
        List(selection: $selectedWorktreeID) {
            ForEach(projects) { project in
                Section {
                    ForEach(project.worktrees.sorted(by: { $0.createdAt < $1.createdAt })) { worktree in
                        WorktreeRow(
                            worktree: worktree,
                            isRunning: runningWorktreeIds.contains(worktree.branchName)
                        )
                            .tag(worktree.branchName)
                            .contextMenu {
                                Button("Delete Worktree", role: .destructive) {
                                    deleteWorktree(worktree, from: project)
                                }
                            }
                    }
                } header: {
                    HStack {
                        ProjectRow(project: project)
                        Spacer()
                        Button {
                            worktreeTargetProject = project
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("New Worktree")
                    }
                    .contextMenu {
                        Button("Project Settings...") {
                            editingProject = project
                        }
                        Divider()
                        Button("Delete Project", role: .destructive) {
                            deleteProject(project)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    showingAddProject = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(12)
                Spacer()
            }
        }
        .sheet(item: $worktreeTargetProject) { project in
            CreateWorktreeView(project: project)
        }
        .sheet(item: $editingProject) { project in
            ProjectSettingsView(project: project)
        }
    }

    private func deleteWorktree(_ worktree: Worktree, from project: Project) {
        modelContext.delete(worktree)
        try? modelContext.save()
    }

    private func deleteProject(_ project: Project) {
        modelContext.delete(project)
        try? modelContext.save()
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack {
            Image(systemName: project.isRemote ? "globe" : "folder.fill")
                .foregroundStyle(.secondary)
                .font(.title3)
            Text(project.name)
                .font(.title3)
                .fontWeight(.medium)
        }
    }
}

struct WorktreeRow: View {
    let worktree: Worktree
    var isRunning: Bool = false

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(worktree.branchName)
                        .lineLimit(1)
                    if isRunning {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(worktree.baseBranch)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusIcon: String {
        switch worktree.status {
        case .creating: "circle.dotted"
        case .ready: "circle"
        case .active: "circle.fill"
        case .archived: "archivebox"
        case .error: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch worktree.status {
        case .creating: .orange
        case .ready: .secondary
        case .active: .green
        case .archived: .gray
        case .error: .red
        }
    }
}
