import SwiftUI
import SwiftData
import WTCore
import WTGit
import WTTransport
import os.log

private let logger = Logger(subsystem: "com.wtmux", category: "CreateWorktreeView")

struct CreateWorktreeView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var branchName = ""
    @State private var baseBranch = ""
    @State private var availableBranches: [String] = []
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
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

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .labelsHidden()
            .padding()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { createWorktree() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(branchName.isEmpty || baseBranch.isEmpty || isCreating)
            }
            .padding()
        }
        .frame(width: 400)
        .task {
            await loadBranches()
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

        Task {
            let transport = LocalTransport()
            let git = GitService(transport: transport, repoPath: project.repoPath)

            let worktreePath = "\(project.worktreeBasePath)/\(branchName)"

            do {
                try await git.worktreeAdd(
                    path: worktreePath,
                    branch: branchName,
                    baseBranch: baseBranch
                )

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

                let worktree = Worktree(
                    branchName: branchName,
                    path: worktreePath,
                    baseBranch: baseBranch,
                    status: .ready
                )
                if !(project.profile?.setupCommands ?? []).isEmpty {
                    worktree.needsSetup = true
                }
                worktree.project = project
                modelContext.insert(worktree)
                do {
                    try modelContext.save()
                } catch {
                    logger.error("Failed to save new worktree '\(branchName)': \(error.localizedDescription)")
                }

                await MainActor.run {
                    dismiss()
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
