import AppKit
import SwiftUI
import SwiftData
import WTCore
import WTGit
import WTTerminal
import WTTransport
import os.log

private let logger = Logger(subsystem: "com.wtmux", category: "SidebarView")

struct SidebarView: View {
    let projects: [Project]
    @Binding var selectedWorktreeID: String?
    @Binding var showingAddProject: Bool
    @Binding var showRunnerPanel: Bool
    let terminalSessionManager: TerminalSessionManager
    let claudeStatusManager: ClaudeStatusManager

    @Environment(\.modelContext) private var modelContext
    @State private var worktreeTargetProject: Project?
    @State private var editingProject: Project?
    @State private var worktreeToDelete: Worktree?
    @State private var deleteWorktreeBranch = true
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var projectToDelete: Project?
    @State private var deleteProjectBranches = true
    @State private var projectDeleteError: String?
    @State private var showProjectDeleteError = false
    @State private var showRunnerConflictAlert = false
    @State private var conflictingWorktreeName = ""
    @State private var conflictingPorts: [Int] = []
    @State private var worktreeToStartRunners: Worktree?

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
                            hasRunConfigurations: hasRunConfigurations(for: worktree),
                            onStartRunners: {
                                selectedWorktreeID = worktree.path
                                showRunnerPanel = true
                                requestStartRunners(for: worktree)
                            },
                            onStopRunners: { stopRunners(for: worktree) }
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
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderless)
                        .help("New Worktree")
                    }
                    .contextMenu {
                        Button("Project Settings...") {
                            editingProject = project
                        }
                        Divider()
                        Button("Delete Project...", role: .destructive) {
                            deleteProjectBranches = true
                            projectToDelete = project
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
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .padding(14)
                Spacer()
            }
        }
        .sheet(item: $worktreeTargetProject) { project in
            CreateWorktreeView(project: project)
        }
        .sheet(item: $editingProject) { project in
            ProjectSettingsView(project: project)
        }
        .sheet(item: $worktreeToDelete) { wt in
            DeleteWorktreeSheet(
                worktreeName: wt.branchName,
                deleteBranch: $deleteWorktreeBranch,
                onDelete: {
                    let shouldDeleteBranch = deleteWorktreeBranch
                    worktreeToDelete = nil
                    Task { await deleteWorktreeWithGit(wt, deleteBranch: shouldDeleteBranch) }
                },
                onCancel: {
                    worktreeToDelete = nil
                }
            )
        }
        .alert("Delete Failed", isPresented: $showDeleteError) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "An unknown error occurred.")
        }
        .sheet(item: $projectToDelete) { project in
            DeleteProjectSheet(
                projectName: project.name,
                worktreeCount: project.worktrees.count,
                deleteBranches: $deleteProjectBranches,
                onDeleteEverything: {
                    let shouldDeleteBranches = deleteProjectBranches
                    projectToDelete = nil
                    Task { await deleteProjectWithWorktrees(project, deleteBranches: shouldDeleteBranches) }
                },
                onRemoveFromApp: {
                    projectToDelete = nil
                    deleteProjectOnly(project)
                },
                onCancel: {
                    projectToDelete = nil
                }
            )
        }
        .alert("Project Deletion Error", isPresented: $showProjectDeleteError) {
            Button("OK") { projectDeleteError = nil }
        } message: {
            Text(projectDeleteError ?? "An unknown error occurred.")
        }
        .alert("Runners Already Active", isPresented: $showRunnerConflictAlert) {
            Button("Stop & Switch") {
                if let worktree = worktreeToStartRunners {
                    stopConflictingAndStartRunners(for: worktree)
                }
                worktreeToStartRunners = nil
            }
            Button("Cancel", role: .cancel) {
                worktreeToStartRunners = nil
            }
        } message: {
            if conflictingPorts.isEmpty {
                Text("Worktree \"\(conflictingWorktreeName)\" is already running. Starting runners here may cause port conflicts.")
            } else {
                let ports = conflictingPorts.map(String.init).joined(separator: ", ")
                Text("Worktree \"\(conflictingWorktreeName)\" is already using port\(conflictingPorts.count > 1 ? "s" : "") \(ports). Stop its runners and start here instead?")
            }
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
            deleteWorktreeBranch = true
            worktreeToDelete = worktree
        } label: {
            Label("Delete Worktree...", systemImage: "trash")
        }
    }

    // MARK: - Runner Helpers

    private func hasRunConfigurations(for worktree: Worktree) -> Bool {
        !(worktree.project?.profile?.runConfigurations.isEmpty ?? true)
    }

    private func requestStartRunners(for worktree: Worktree) {
        if let conflict = conflictingWorktree(for: worktree) {
            worktreeToStartRunners = worktree
            conflictingWorktreeName = conflict.branchName
            conflictingPorts = conflictingPortList(for: worktree)
            showRunnerConflictAlert = true
            return
        }
        startRunners(for: worktree)
    }

    /// Finds another worktree in the same project that has running runners.
    private func conflictingWorktree(for worktree: Worktree) -> Worktree? {
        guard let project = worktree.project else { return nil }
        let _ = terminalSessionManager.runnerStateVersion
        for sibling in project.worktrees where sibling.path != worktree.path {
            let runners = terminalSessionManager.runnerSessions(forWorktree: sibling.path)
            if runners.contains(where: { $0.isProcessRunning }) {
                return sibling
            }
        }
        return nil
    }

    private func conflictingPortList(for worktree: Worktree) -> [Int] {
        guard let configs = worktree.project?.profile?.runConfigurations else { return [] }
        return configs.compactMap(\.port).sorted()
    }

    private func stopConflictingAndStartRunners(for worktree: Worktree) {
        guard let project = worktree.project else { return }
        for sibling in project.worktrees where sibling.path != worktree.path {
            for session in terminalSessionManager.runnerSessions(forWorktree: sibling.path) {
                terminalSessionManager.stopSession(id: session.id)
            }
            terminalSessionManager.removeRunnerSessions(forWorktree: sibling.path)
        }
        startRunners(for: worktree)
    }

    private func startRunners(for worktree: Worktree) {
        guard let configs = worktree.project?.profile?.runConfigurations
            .sorted(by: { $0.order < $1.order }) else { return }
        for config in configs where !config.command.isEmpty {
            let sessionId = SessionID.runner(worktreeId: worktree.path, name: config.name)
            guard terminalSessionManager.sessions[sessionId] == nil else { continue }
            let session = terminalSessionManager.createRunnerSession(
                id: sessionId,
                title: config.name,
                worktreeId: worktree.path,
                workingDirectory: worktree.path,
                initialCommand: config.command,
                deferExecution: true
            )
            session.onProcessExit = { [weak terminalSessionManager] sessionId, exitCode in
                terminalSessionManager?.handleProcessExit(sessionId: sessionId, exitCode: exitCode)
            }
        }
        // Defer startSession to next run loop so terminal views have time to render
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            for config in configs where !config.command.isEmpty {
                let sessionId = SessionID.runner(worktreeId: worktree.path, name: config.name)
                terminalSessionManager.startSession(id: sessionId)
            }
        }
    }

    private func stopRunners(for worktree: Worktree) {
        for session in terminalSessionManager.runnerSessions(forWorktree: worktree.path) {
            terminalSessionManager.stopSession(id: session.id)
        }
    }

    // MARK: - Delete

    private func deleteWorktreeWithGit(_ worktree: Worktree, deleteBranch: Bool = false) async {
        let branchName = worktree.branchName
        let repoPath = worktree.project?.repoPath

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
        if let repoPath {
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

            // 4. Optionally delete branch
            if deleteBranch {
                do {
                    try await git.branchDelete(name: branchName)
                } catch {
                    logger.warning("Could not delete branch '\(branchName)': \(error.localizedDescription)")
                }
            }
        }

        // 5. Delete from SwiftData and clear selection
        await MainActor.run {
            if selectedWorktreeID == worktree.path {
                selectedWorktreeID = nil
            }
            modelContext.delete(worktree)
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save after deleting worktree '\(branchName)': \(error.localizedDescription)")
            }
            worktreeToDelete = nil
        }
    }

    private func deleteProjectOnly(_ project: Project) {
        // Clean up terminal sessions for all worktrees
        for worktree in project.worktrees {
            for session in terminalSessionManager.runnerSessions(forWorktree: worktree.path) {
                terminalSessionManager.stopSession(id: session.id)
            }
            terminalSessionManager.removeRunnerSessions(forWorktree: worktree.path)
            for session in terminalSessionManager.sessions(forWorktree: worktree.path) {
                terminalSessionManager.removeTab(sessionId: session.id)
            }
            if selectedWorktreeID == worktree.path {
                selectedWorktreeID = nil
            }
        }

        modelContext.delete(project)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save after deleting project '\(project.name)': \(error.localizedDescription)")
        }
        projectToDelete = nil
    }

    private func deleteProjectWithWorktrees(_ project: Project, deleteBranches: Bool) async {
        var errors: [String] = []
        let repoPath = project.repoPath
        let git = GitService(transport: LocalTransport(), repoPath: repoPath)
        let worktrees = project.worktrees

        for worktree in worktrees {
            // Stop runners and terminals
            for session in terminalSessionManager.runnerSessions(forWorktree: worktree.path) {
                terminalSessionManager.stopSession(id: session.id)
            }
            terminalSessionManager.removeRunnerSessions(forWorktree: worktree.path)
            for session in terminalSessionManager.sessions(forWorktree: worktree.path) {
                terminalSessionManager.removeTab(sessionId: session.id)
            }

            // Remove git worktree
            do {
                try await git.worktreeRemove(path: worktree.path)
            } catch {
                do {
                    try await git.worktreeRemove(path: worktree.path, force: true)
                } catch {
                    errors.append("Worktree \(worktree.branchName): \(error.localizedDescription)")
                }
            }

            // Optionally delete branch
            if deleteBranches {
                do {
                    try await git.branchDelete(name: worktree.branchName)
                } catch {
                    logger.warning("Could not delete branch '\(worktree.branchName)': \(error.localizedDescription)")
                }
            }
        }

        await MainActor.run {
            if let sel = selectedWorktreeID, worktrees.contains(where: { $0.path == sel }) {
                selectedWorktreeID = nil
            }
            modelContext.delete(project)
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save after deleting project '\(project.name)': \(error.localizedDescription)")
            }
            projectToDelete = nil

            if !errors.isEmpty {
                projectDeleteError = "Some items could not be removed:\n" + errors.joined(separator: "\n")
                showProjectDeleteError = true
            }
        }
    }
}

extension Color {
    static func fromPaletteName(_ name: String?) -> Color? {
        switch name {
        case "blue": .blue
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "teal": .teal
        case "pink": .pink
        case "indigo": .indigo
        case "cyan": .cyan
        default: nil
        }
    }
}

private let projectColorPalette: [Color] = [
    .blue,
    .green,
    .orange,
    .purple,
    .teal,
    .pink,
    .indigo,
    .cyan,
]

private func projectColor(for project: Project) -> Color {
    if let color = Color.fromPaletteName(project.colorName) {
        return color
    }
    let index = abs(project.name.hashValue) % projectColorPalette.count
    return projectColorPalette[index]
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(projectColor(for: project))
                .frame(width: 4, height: 14)
            Image(systemName: project.resolvedIconName)
                .foregroundStyle(projectColor(for: project))
                .font(.title3)
            Text(project.name)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }
}

struct WorktreeRow: View {
    let worktree: Worktree
    var isRunning: Bool = false
    var claudeStatus: ClaudeCodeStatus? = nil
    var hasRunConfigurations: Bool = false
    var onStartRunners: (() -> Void)? = nil
    var onStopRunners: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(worktree.branchName)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let claudeStatus {
                        claudeBadge(claudeStatus)
                    }
                }
                Text(worktree.baseBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isHovered, hasRunConfigurations {
                if isRunning, let onStopRunners {
                    Button {
                        onStopRunners()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop Runners")
                } else if let onStartRunners {
                    Button {
                        onStartRunners()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Start Runners")
                }
            }
            if isRunning {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                    .help("Runners active")
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
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        case .thinking:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.purple)
                .symbolEffect(.pulse)
        case .working:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .needsAttention:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Delete Worktree Sheet

struct DeleteWorktreeSheet: View {
    let worktreeName: String
    @Binding var deleteBranch: Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text("Delete Worktree?")
                .font(.headline)

            Text("This will remove the worktree \"\(worktreeName)\" and delete its directory from disk. Any uncommitted changes will be lost.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Also delete branch \"\(worktreeName)\"", isOn: $deleteBranch)
                .padding(.horizontal)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Delete", role: .destructive, action: onDelete)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

// MARK: - Delete Project Sheet

struct DeleteProjectSheet: View {
    let projectName: String
    let worktreeCount: Int
    @Binding var deleteBranches: Bool
    let onDeleteEverything: () -> Void
    let onRemoveFromApp: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text("Delete Project \"\(projectName)\"?")
                .font(.headline)

            if worktreeCount > 0 {
                Text("This project has \(worktreeCount) worktree\(worktreeCount == 1 ? "" : "s"). You can remove all worktrees from disk or just remove the project from WTMux.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Also delete worktree branches", isOn: $deleteBranches)
                    .padding(.horizontal)
            } else {
                Text("This will remove the project from WTMux.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if worktreeCount > 0 {
                    Button("Remove from App Only", action: onRemoveFromApp)
                    Button("Delete Everything", role: .destructive, action: onDeleteEverything)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Delete", role: .destructive, action: onRemoveFromApp)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
