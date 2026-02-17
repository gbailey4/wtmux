import SwiftUI
import SwiftData
import AppKit
import WTCore
import WTGit
import WTTransport
import os.log

private let logger = Logger(subsystem: "com.wtmux", category: "CreateWorktreeView")

enum WorktreeCreationMode: String, CaseIterable {
    case newBranch = "New Branch"
    case existingBranch = "Existing Branch"
}

struct CreateWorktreeView: View {
    let project: Project
    let paneManager: SplitPaneManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var creationMode: WorktreeCreationMode = .newBranch
    @State private var branchName = ""
    @State private var baseBranch = ""
    @State private var selectedExistingBranch = ""
    @State private var availableBranches: [String] = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var checkedOutConflict: CheckedOutConflict?

    struct CheckedOutConflict {
        let branch: String
        let conflictPath: String
        let command: String
    }

    private var isCreateDisabled: Bool {
        if isCreating { return true }
        switch creationMode {
        case .newBranch: return branchName.isEmpty || baseBranch.isEmpty
        case .existingBranch: return selectedExistingBranch.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Mode", selection: $creationMode) {
                    ForEach(WorktreeCreationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch creationMode {
                case .newBranch:
                    TextField("Branch Name", text: $branchName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Base Branch")
                        Picker("Base Branch", selection: $baseBranch) {
                            ForEach(availableBranches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                    }

                case .existingBranch:
                    HStack {
                        Text("Branch")
                        Picker("Branch", selection: $selectedExistingBranch) {
                            Text("Select a branch").tag("")
                            ForEach(availableBranches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                    }
                }

                if let conflict = checkedOutConflict {
                    checkedOutConflictView(conflict)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .labelsHidden()
            .padding()
            .onChange(of: creationMode) {
                errorMessage = nil
                checkedOutConflict = nil
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(creationMode == .existingBranch ? "Open" : "Create") { createWorktree() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCreateDisabled)
            }
            .padding()
        }
        .frame(width: 400)
        .task {
            await loadBranches()
        }
    }

    @ViewBuilder
    private func checkedOutConflictView(_ conflict: CheckedOutConflict) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Branch \"\(conflict.branch)\" is already checked out at:")
                .foregroundStyle(.red)
                .font(.caption)

            Text(conflict.conflictPath)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            Text("To free it up, run:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(conflict.command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(conflict.command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy command")
            }

            Text("If you had uncommitted changes, recover them with `git stash pop` in the new worktree.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func loadBranches() async {
        let transport = LocalTransport()
        let git = GitService(transport: transport, repoPath: project.repoPath)
        do {
            availableBranches = try await git.branches()
            baseBranch = project.defaultBranch
            if !availableBranches.contains(baseBranch), let first = availableBranches.first {
                baseBranch = first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createWorktree() {
        isCreating = true
        errorMessage = nil
        checkedOutConflict = nil

        let isExisting = creationMode == .existingBranch

        Task {
            let transport = LocalTransport()
            let git = GitService(transport: transport, repoPath: project.repoPath)

            let effectiveBranch: String
            let effectiveBaseBranch: String
            let worktreePath: String

            if isExisting {
                effectiveBranch = selectedExistingBranch
                effectiveBaseBranch = project.defaultBranch
                worktreePath = "\(project.worktreeBasePath)/\(selectedExistingBranch)"
            } else {
                effectiveBranch = branchName
                effectiveBaseBranch = baseBranch
                worktreePath = "\(project.worktreeBasePath)/\(branchName)"
            }

            do {
                if isExisting {
                    try await git.worktreeAddExisting(
                        path: worktreePath,
                        branch: effectiveBranch
                    )
                } else {
                    try await git.worktreeAdd(
                        path: worktreePath,
                        branch: effectiveBranch,
                        baseBranch: effectiveBaseBranch
                    )
                }

                // Apply profile: copy env files from main repo to new worktree
                let envFiles = project.profile?.envFilesToCopy ?? []
                if !envFiles.isEmpty {
                    let applicator = ProfileApplicator()
                    applicator.applyEnvFiles(
                        envFiles: envFiles,
                        repoPath: project.repoPath,
                        worktreePath: worktreePath
                    )
                }

                let nextOrder = (project.worktrees.map(\.sortOrder).max() ?? -1) + 1
                let worktree = Worktree(
                    branchName: effectiveBranch,
                    path: worktreePath,
                    baseBranch: effectiveBaseBranch,
                    status: .ready,
                    sortOrder: nextOrder
                )
                if !(project.profile?.setupCommands ?? []).isEmpty {
                    worktree.needsSetup = true
                }
                worktree.project = project
                modelContext.insert(worktree)
                do {
                    try modelContext.save()
                } catch {
                    logger.error("Failed to save new worktree '\(effectiveBranch)': \(error.localizedDescription)")
                }

                await MainActor.run {
                    paneManager.openWorktreeInNewWindow(worktreeID: worktreePath)
                    dismiss()
                }
            } catch let error as GitError {
                await MainActor.run {
                    if case .branchAlreadyCheckedOut(let branch, let path) = error {
                        let defaultBranch = project.defaultBranch
                        checkedOutConflict = CheckedOutConflict(
                            branch: branch,
                            conflictPath: path,
                            command: "cd \(path) && git stash; git checkout \(defaultBranch)"
                        )
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    isCreating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
