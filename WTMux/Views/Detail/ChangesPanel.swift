import SwiftUI
import WTCore
import WTGit
import WTDiff
import WTTransport
import WTSSH
struct SelectedFile: Equatable {
    let groupId: String
    let path: String
}

enum ChangeGroup: Identifiable {
    case workingChanges(files: [GitFileStatus])
    case commit(info: GitCommitInfo, files: [GitFileStatus])
    case worktreeVsBase(files: [GitFileStatus], baseBranch: String)

    var id: String {
        switch self {
        case .workingChanges:
            return "working-changes"
        case .commit(let info, _):
            return info.id
        case .worktreeVsBase:
            return "worktree-vs-base"
        }
    }

    var files: [GitFileStatus] {
        switch self {
        case .workingChanges(let files):
            return files
        case .commit(_, let files):
            return files
        case .worktreeVsBase(let files, _):
            return files
        }
    }
}

enum DiffViewMode: Hashable {
    case byCommit
    case worktreeVsBase
}

struct ChangesPanel: View {
    let worktree: Worktree
    let paneManager: SplitPaneManager
    let paneID: UUID
    @Binding var changedFileCount: Int

    @Environment(\.sshConnectionManager) private var sshConnectionManager

    @State private var diffViewMode: DiffViewMode = .byCommit
    @State private var changeGroups: [ChangeGroup] = []
    @State private var diffCache: [String: [DiffFile]] = [:]
    @State private var selectedFile: SelectedFile?
    @State private var expandedGroups: Set<String> = ["working-changes"]
    @State private var isLoading = false
    @State private var commitFileCache: [String: [GitFileStatus]] = [:]

    private var git: GitService {
        let transport: CommandTransport = worktree.project.map { $0.makeTransport(connectionManager: sshConnectionManager) } ?? LocalTransport()
        return GitService(transport: transport, repoPath: worktree.path)
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
                    description: Text(emptyStateDescription)
                )
            } else {
                outlineView
            }
        }
        .task(id: "\(worktree.path)-\(diffViewMode)") {
            await loadAllChanges()
        }
        .onChange(of: paneManager.activeDiffFile?.id) { _, newValue in
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
            Picker("", selection: $diffViewMode) {
                Text("By Commit").tag(DiffViewMode.byCommit)
                Text("vs \(worktree.baseBranch)").tag(DiffViewMode.worktreeVsBase)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
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
                       let file = diffFiles.first(where: {
                           $0.displayPath == path || $0.id == path || $0.oldPath == path || $0.newPath == path
                       }) {
                        paneManager.showDiff(file: file, worktreePath: worktree.path, fromPane: paneID)
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
        case .worktreeVsBase(let files, _):
            return files
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
        case .worktreeVsBase(_, let baseBranch):
            HStack(spacing: 4) {
                Text("vs \(baseBranch)")
                    .fontWeight(.medium)
                Spacer()
                Text("\(group.files.count)")
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
        changedFileCount = 0
        defer { isLoading = false }

        var groups: [ChangeGroup] = []
        let baseBranch = worktree.baseBranch

        do {
            switch diffViewMode {
            case .byCommit:
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

            case .worktreeVsBase:
                let diffOutput = try await git.worktreeDiffVsBranch(baseBranch)
                let parser = DiffParser()
                let diffFiles = parser.parse(diffOutput)
                var files = diffFiles.map { gitFileStatus(from: $0) }

                let statusFiles = try await git.status()
                let existingPaths = Set(files.map(\.path))
                for statusFile in statusFiles where statusFile.status == .untracked {
                    if !existingPaths.contains(statusFile.path) {
                        files.append(statusFile)
                    }
                }

                if !files.isEmpty {
                    groups.append(.worktreeVsBase(files: files, baseBranch: baseBranch))
                }
            }
        } catch {
            // Silently handle errors — the panel will show empty state
        }

        changeGroups = groups

        // Update badge count
        let count: Int
        switch diffViewMode {
        case .byCommit:
            count = groups.first(where: { $0.id == "working-changes" })?.files.count ?? 0
        case .worktreeVsBase:
            count = groups.first(where: { $0.id == "worktree-vs-base" })?.files.count ?? 0
        }
        changedFileCount = count

        if groups.isEmpty {
            expandedGroups = []
        } else {
            expandedGroups = [groups[0].id]
        }
        selectedFile = nil
        diffCache = [:]
        commitFileCache = [:]
    }

    private func gitFileStatus(from diffFile: DiffFile) -> GitFileStatus {
        let status: FileStatusKind
        let path: String
        if diffFile.oldPath == "dev/null" {
            status = .added
            path = diffFile.newPath
        } else if diffFile.newPath == "dev/null" {
            status = .deleted
            path = diffFile.oldPath
        } else if diffFile.oldPath != diffFile.newPath {
            status = .renamed
            path = diffFile.newPath
        } else {
            status = .modified
            path = diffFile.displayPath
        }
        return GitFileStatus(path: path, status: status)
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
            } else if groupId == "worktree-vs-base" {
                diffOutput = try await git.worktreeDiffVsBranch(worktree.baseBranch)
            } else {
                diffOutput = try await git.commitDiff(hash: groupId)
            }
            let parser = DiffParser()
            var parsed = parser.parse(diffOutput)

            // Synthesize diffs for untracked files (git diff doesn't include them)
            if groupId == "working-changes" || groupId == "worktree-vs-base" {
                let workingFiles = changeGroups.first(where: { $0.id == groupId })?.files ?? []
                for file in workingFiles where file.status == .untracked {
                    guard !parsed.contains(where: { $0.displayPath == file.path || $0.id == file.path }) else { continue }
                    if let synthetic = syntheticDiffFile(relativePath: file.path) {
                        parsed.append(synthetic)
                    }
                }
            }

            diffCache[groupId] = parsed
        } catch {
            diffCache[groupId] = []
        }
    }

    private func syntheticDiffFile(relativePath: String) -> DiffFile? {
        let fullPath = (worktree.path as NSString).appendingPathComponent(relativePath)
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { return nil }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        var diffLines: [DiffLine] = []
        for (i, line) in lines.enumerated() {
            diffLines.append(DiffLine(
                id: "0-\(i)",
                kind: .addition,
                content: String(line),
                oldLineNumber: nil,
                newLineNumber: i + 1
            ))
        }

        let hunk = DiffHunk(
            id: "0",
            header: "@@ -0,0 +1,\(lines.count) @@",
            oldStart: 0,
            oldCount: 0,
            newStart: 1,
            newCount: lines.count,
            lines: diffLines
        )

        return DiffFile(
            id: relativePath,
            oldPath: "/dev/null",
            newPath: relativePath,
            hunks: [hunk]
        )
    }

    private func refresh() async {
        diffCache = [:]
        commitFileCache = [:]
        selectedFile = nil
        paneManager.closeDiff()
        await loadAllChanges()
    }

    // MARK: - Helpers

    private var emptyStateDescription: String {
        switch diffViewMode {
        case .byCommit:
            return "Working directory is clean and no commits ahead of \(worktree.baseBranch)"
        case .worktreeVsBase:
            return "Worktree matches \(worktree.baseBranch)"
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func relativeDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
