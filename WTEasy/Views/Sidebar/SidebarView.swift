import AppKit
import SwiftUI
import SwiftData
import WTCore
import WTGit
import WTTerminal
import WTTransport
import os.log

private let logger = Logger(subsystem: "com.wteasy", category: "SidebarView")

struct SidebarView: View {
    let projects: [Project]
    @Binding var selectedWorktreeID: String?
    @Binding var showingAddProject: Bool
    let terminalSessionManager: TerminalSessionManager
    let claudeStatusManager: ClaudeStatusManager

    @Environment(\.modelContext) private var modelContext
    @State private var worktreeTargetProject: Project?
    @State private var editingProject: Project?
    @State private var worktreeToDelete: Worktree?
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var showDeleteError = false

    private var runningWorktreeIds: Set<String> {
        // Read runnerStateVersion to trigger re-evaluation when runners stop/restart
        let _ = terminalSessionManager.runnerStateVersion
        return terminalSessionManager.worktreeIdsWithRunners()
    }

    var body: some View {
        List(selection: $selectedWorktreeID) {
            ForEach(projects) { project in
                Section {
                    ForEach(project.worktrees.sorted(by: { $0.createdAt < $1.createdAt })) { worktree in
                        WorktreeRow(
                            worktree: worktree,
                            isRunning: runningWorktreeIds.contains(worktree.path),
                            claudeStatus: claudeStatusManager.status(forWorktreePath: worktree.path),
                            onDelete: {
                                worktreeToDelete = worktree
                                showDeleteConfirmation = true
                            }
                        )
                            .tag(worktree.path)
                            .contextMenu {
                                worktreeContextMenu(worktree: worktree)
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
        .alert("Delete Worktree?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let wt = worktreeToDelete {
                    Task { await deleteWorktreeWithGit(wt) }
                }
            }
            Button("Cancel", role: .cancel) {
                worktreeToDelete = nil
            }
        } message: {
            if let wt = worktreeToDelete {
                Text("This will remove the worktree \"\(wt.branchName)\" and delete its directory from disk. Any uncommitted changes will be lost.")
            }
        }
        .alert("Delete Failed", isPresented: $showDeleteError) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func worktreeContextMenu(worktree: Worktree) -> some View {
        let isRunning = runningWorktreeIds.contains(worktree.path)

        if hasRunConfigurations(for: worktree) {
            if isRunning {
                Button {
                    stopRunners(for: worktree)
                } label: {
                    Label("Stop Runners", systemImage: "stop.fill")
                }
            } else {
                Button {
                    selectedWorktreeID = worktree.path
                    startRunners(for: worktree)
                } label: {
                    Label("Start Runners", systemImage: "play.fill")
                }
            }

            Divider()
        }

        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
        } label: {
            Label("Open in Finder", systemImage: "folder")
        }

        let editors = ExternalEditor.installedEditors(custom: ExternalEditor.customEditors)
        if !editors.isEmpty {
            Menu {
                ForEach(editors) { editor in
                    Button(editor.name) {
                        let folderURL = URL(fileURLWithPath: worktree.path, isDirectory: true)
                        ExternalEditor.open(fileURL: folderURL, editor: editor)
                    }
                }
            } label: {
                Label("Open in Editor", systemImage: "arrow.up.forward.square")
            }
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            worktreeToDelete = worktree
            showDeleteConfirmation = true
        } label: {
            Label("Delete Worktree...", systemImage: "trash")
        }
    }

    // MARK: - Runner Helpers

    private func hasRunConfigurations(for worktree: Worktree) -> Bool {
        !(worktree.project?.profile?.runConfigurations.isEmpty ?? true)
    }

    private func startRunners(for worktree: Worktree) {
        guard let configs = worktree.project?.profile?.runConfigurations
            .sorted(by: { $0.order < $1.order }) else { return }
        for config in configs where !config.command.isEmpty {
            let sessionId = "runner-\(worktree.path)-\(config.name)"
            guard terminalSessionManager.sessions[sessionId] == nil else { continue }
            let session = terminalSessionManager.createRunnerSession(
                id: sessionId,
                title: config.name,
                worktreeId: worktree.path,
                workingDirectory: worktree.path,
                initialCommand: config.command
            )
            session.onProcessExit = { [weak terminalSessionManager] sessionId, exitCode in
                terminalSessionManager?.handleProcessExit(sessionId: sessionId, exitCode: exitCode)
            }
        }
    }

    private func stopRunners(for worktree: Worktree) {
        for session in terminalSessionManager.runnerSessions(forWorktree: worktree.path) {
            terminalSessionManager.stopSession(id: session.id)
        }
    }

    // MARK: - Delete

    private func deleteWorktreeWithGit(_ worktree: Worktree) async {
        // 1. Stop and remove all runner sessions
        for session in terminalSessionManager.runnerSessions(forWorktree: worktree.path) {
            terminalSessionManager.stopSession(id: session.id)
        }
        terminalSessionManager.removeRunnerSessions(forWorktree: worktree.path)

        // 2. Remove terminal tab sessions
        for session in terminalSessionManager.sessions(forWorktree: worktree.path) {
            terminalSessionManager.removeTab(sessionId: session.id)
        }

        // 3. Call git worktree remove
        if let repoPath = worktree.project?.repoPath {
            let git = GitService(transport: LocalTransport(), repoPath: repoPath)
            do {
                try await git.worktreeRemove(path: worktree.path)
            } catch {
                // Retry with force (handles uncommitted changes)
                do {
                    try await git.worktreeRemove(path: worktree.path, force: true)
                } catch {
                    await MainActor.run {
                        deleteError = error.localizedDescription
                        showDeleteError = true
                        worktreeToDelete = nil
                    }
                    return
                }
            }
        }

        // 4. Delete from SwiftData and clear selection
        await MainActor.run {
            if selectedWorktreeID == worktree.path {
                selectedWorktreeID = nil
            }
            modelContext.delete(worktree)
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save after deleting worktree '\(worktree.branchName)': \(error.localizedDescription)")
            }
            worktreeToDelete = nil
        }
    }

    private func deleteProject(_ project: Project) {
        modelContext.delete(project)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save after deleting project '\(project.name)': \(error.localizedDescription)")
        }
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
    var claudeStatus: ClaudeCodeStatus? = nil
    var onDelete: (() -> Void)?

    @State private var isHovered = false

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
                    if let claudeStatus {
                        claudeBadge(claudeStatus)
                    }
                }
                Text(worktree.baseBranch)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isHovered, let onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete Worktree")
            }
        }
        .onHover { hovering in
            isHovered = hovering
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

    @ViewBuilder
    private func claudeBadge(_ status: ClaudeCodeStatus) -> some View {
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
