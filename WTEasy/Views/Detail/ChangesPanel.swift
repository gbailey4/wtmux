import SwiftUI
import WTCore
import WTGit
import WTDiff
import WTTransport
struct SelectedFile: Equatable {
    let groupId: String
    let path: String
}

enum ChangeGroup: Identifiable {
    case workingChanges(files: [GitFileStatus])
    case commit(info: GitCommitInfo, files: [GitFileStatus])

    var id: String {
        switch self {
        case .workingChanges:
            return "working-changes"
        case .commit(let info, _):
            return info.id
        }
    }

    var files: [GitFileStatus] {
        switch self {
        case .workingChanges(let files):
            return files
        case .commit(_, let files):
            return files
        }
    }
}

struct ChangesPanel: View {
    let worktree: Worktree
    @Binding var activeDiffFile: DiffFile?

    @State private var changeGroups: [ChangeGroup] = []
    @State private var diffCache: [String: [DiffFile]] = [:]
    @State private var selectedFile: SelectedFile?
    @State private var expandedGroups: Set<String> = ["working-changes"]
    @State private var isLoading = false
    @State private var commitFileCache: [String: [GitFileStatus]] = [:]

    private var git: GitService {
        GitService(transport: LocalTransport(), repoPath: worktree.path)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading && changeGroups.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if changeGroups.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("Working directory is clean and no commits ahead of \(worktree.baseBranch)")
                )
            } else {
                outlineView
            }
        }
        .task(id: worktree.branchName) {
            await loadAllChanges()
        }
        .onChange(of: activeDiffFile?.id) { _, newValue in
            if newValue == nil {
                selectedFile = nil
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Changes")
                .font(.headline)
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(8)
        .background(.bar)
    }

    // MARK: - Outline

    @ViewBuilder
    private var outlineView: some View {
        List(selection: Binding(
            get: { selectedFile.map { "\($0.groupId):\($0.path)" } },
            set: { newValue in
                guard let newValue else { selectedFile = nil; return }
                let parts = newValue.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { return }
                let groupId = String(parts[0])
                let path = String(parts[1])
                selectedFile = SelectedFile(groupId: groupId, path: path)
                Task {
                    await loadDiffIfNeeded(groupId: groupId)
                    if let diffFiles = diffCache[groupId],
                       let file = diffFiles.first(where: { $0.displayPath == path || $0.id == path }) {
                        activeDiffFile = file
                    }
                }
            }
        )) {
            ForEach(changeGroups) { group in
                Section(isExpanded: Binding(
                    get: { expandedGroups.contains(group.id) },
                    set: { expanded in
                        if expanded {
                            expandedGroups.insert(group.id)
                            if case .commit(let info, let files) = group, files.isEmpty {
                                Task { await loadCommitFiles(hash: info.id) }
                            }
                        } else {
                            expandedGroups.remove(group.id)
                        }
                    }
                )) {
                    let files = filesForGroup(group)
                    ForEach(files) { file in
                        fileRow(file: file)
                            .tag("\(group.id):\(file.path)")
                    }
                } header: {
                    groupHeader(group: group)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func filesForGroup(_ group: ChangeGroup) -> [GitFileStatus] {
        switch group {
        case .workingChanges(let files):
            return files
        case .commit(let info, _):
            return commitFileCache[info.id] ?? group.files
        }
    }

    @ViewBuilder
    private func groupHeader(group: ChangeGroup) -> some View {
        switch group {
        case .workingChanges(let files):
            HStack(spacing: 4) {
                Text("Working Changes")
                    .fontWeight(.medium)
                Spacer()
                Text("\(files.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        case .commit(let info, _):
            HStack(spacing: 4) {
                Text(info.shortHash)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(info.message)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(relativeDate(info.date))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func fileRow(file: GitFileStatus) -> some View {
        HStack(spacing: 6) {
            statusBadge(file.status)
            Text(file.path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: FileStatusKind) -> some View {
        Text(status.rawValue)
            .font(.system(.caption, design: .monospaced, weight: .bold))
            .foregroundStyle(statusColor(status))
            .frame(width: 16)
    }

    private func statusColor(_ status: FileStatusKind) -> Color {
        switch status {
        case .added, .untracked: .green
        case .modified: .blue
        case .deleted: .red
        case .renamed, .copied: .orange
        case .unmodified: .secondary
        }
    }

    // MARK: - Data Loading

    private func loadAllChanges() async {
        isLoading = true
        defer { isLoading = false }

        var groups: [ChangeGroup] = []

        let baseBranch = worktree.baseBranch

        do {
            async let statusResult = git.status()
            async let logResult = git.log(since: baseBranch)

            let files = try await statusResult
            let commits = try await logResult

            if !files.isEmpty {
                groups.append(.workingChanges(files: files))
            }

            for commit in commits {
                groups.append(.commit(info: commit, files: []))
            }
        } catch {
            // Silently handle errors — the panel will show empty state
        }

        changeGroups = groups

        if groups.isEmpty {
            expandedGroups = []
        } else {
            expandedGroups = ["working-changes"]
        }
        selectedFile = nil
        diffCache = [:]
        commitFileCache = [:]
    }

    private func loadCommitFiles(hash: String) async {
        guard commitFileCache[hash] == nil else { return }
        do {
            let files = try await git.commitFiles(hash: hash)
            commitFileCache[hash] = files
        } catch {
            commitFileCache[hash] = []
        }
    }

    private func loadDiffIfNeeded(groupId: String) async {
        guard diffCache[groupId] == nil else { return }

        do {
            let diffOutput: String
            if groupId == "working-changes" {
                diffOutput = try await git.workingDiff()
            } else {
                diffOutput = try await git.commitDiff(hash: groupId)
            }
            let parser = DiffParser()
            diffCache[groupId] = parser.parse(diffOutput)
        } catch {
            diffCache[groupId] = []
        }
    }

    private func refresh() async {
        diffCache = [:]
        commitFileCache = [:]
        selectedFile = nil
        activeDiffFile = nil
        await loadAllChanges()
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
