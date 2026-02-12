import SwiftUI
import SwiftData
import WTCore

struct SidebarView: View {
    let projects: [Project]
    @Binding var selectedWorktreeID: String?
    @Binding var showingAddProject: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var worktreeTargetProject: Project?

    var body: some View {
        List(selection: $selectedWorktreeID) {
            ForEach(projects) { project in
                Section {
                    ForEach(project.worktrees.sorted(by: { $0.createdAt < $1.createdAt })) { worktree in
                        WorktreeRow(worktree: worktree)
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
    }

    private func deleteWorktree(_ worktree: Worktree, from project: Project) {
        modelContext.delete(worktree)
        try? modelContext.save()
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack {
            Image(systemName: project.isRemote ? "globe" : "folder.fill")
                .foregroundStyle(.secondary)
            Text(project.name)
                .fontWeight(.medium)
        }
    }
}

struct WorktreeRow: View {
    let worktree: Worktree

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(worktree.branchName)
                    .lineLimit(1)
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
