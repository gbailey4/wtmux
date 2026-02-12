import Foundation
import WTTransport

public actor GitService {
    private let transport: CommandTransport
    private let repoPath: String

    public init(transport: CommandTransport, repoPath: String) {
        self.transport = transport
        self.repoPath = repoPath
    }

    public func currentBranch() async throws -> String {
        let result = try await transport.execute(
            ["/usr/bin/git", "rev-parse", "--abbrev-ref", "HEAD"],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func branches() async throws -> [String] {
        let result = try await transport.execute(
            ["/usr/bin/git", "branch", "--format=%(refname:short)"],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
        return result.stdout
            .split(separator: "\n")
            .map(String.init)
    }

    public func defaultBranch() async throws -> String {
        let result = try await transport.execute(
            ["/usr/bin/git", "symbolic-ref", "refs/remotes/origin/HEAD", "--short"],
            in: repoPath
        )
        if result.succeeded {
            let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return branch.replacingOccurrences(of: "origin/", with: "")
        }
        // Fallback: check for main or master
        let branches = try await branches()
        if branches.contains("main") { return "main" }
        if branches.contains("master") { return "master" }
        return branches.first ?? "main"
    }

    public func worktreeList() async throws -> [GitWorktreeInfo] {
        let result = try await transport.execute(
            ["/usr/bin/git", "worktree", "list", "--porcelain"],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
        return parseWorktreeList(result.stdout)
    }

    public func worktreeAdd(path: String, branch: String, baseBranch: String) async throws {
        let result = try await transport.execute(
            ["/usr/bin/git", "worktree", "add", "-b", branch, path, baseBranch],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
    }

    public func worktreeRemove(path: String, force: Bool = false) async throws {
        var args = ["/usr/bin/git", "worktree", "remove", path]
        if force { args.insert("--force", at: 3) }
        let result = try await transport.execute(args, in: repoPath)
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
    }

    public func diff(baseBranch: String, branch: String) async throws -> String {
        let result = try await transport.execute(
            ["/usr/bin/git", "diff", "\(baseBranch)...\(branch)"],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
        return result.stdout
    }

    /// Returns the list of changed files in the working directory (staged + unstaged + untracked).
    public func status() async throws -> [GitFileStatus] {
        let result = try await transport.execute(
            ["/usr/bin/git", "status", "--porcelain=v1"],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
        return parseStatus(result.stdout)
    }

    /// Returns a unified diff of all working changes (staged + unstaged) against HEAD.
    public func workingDiff() async throws -> String {
        let result = try await transport.execute(
            ["/usr/bin/git", "diff", "HEAD"],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
        return result.stdout
    }

    /// Returns commits on the current branch since it diverged from `baseBranch`, newest-first.
    public func log(since baseBranch: String) async throws -> [GitCommitInfo] {
        let result = try await transport.execute(
            ["/usr/bin/git", "log", "\(baseBranch)..HEAD", "--format=%H%n%h%n%an%n%aI%n%s"],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
        return parseLog(result.stdout)
    }

    /// Returns the diff for a single commit (patch only, no commit header).
    public func commitDiff(hash: String) async throws -> String {
        let result = try await transport.execute(
            ["/usr/bin/git", "show", hash, "--format="],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
        return result.stdout
    }

    /// Returns the list of files changed in a single commit.
    public func commitFiles(hash: String) async throws -> [GitFileStatus] {
        let result = try await transport.execute(
            ["/usr/bin/git", "diff-tree", "--no-commit-id", "-r", "--name-status", hash],
            in: repoPath
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr)
        }
        return parseDiffTree(result.stdout)
    }

    // MARK: - Parsers

    private func parseStatus(_ output: String) -> [GitFileStatus] {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var files: [GitFileStatus] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.count >= 4 else { continue }
            let index = line.index(line.startIndex, offsetBy: 0)
            let worktreeChar = line[line.index(line.startIndex, offsetBy: 1)]
            let indexChar = line[index]
            let path = String(line.dropFirst(3))

            // Determine effective status: prefer index status, fall back to worktree status
            let statusChar: Character
            if indexChar == "?" {
                statusChar = "?"
            } else if indexChar != " " {
                statusChar = indexChar
            } else {
                statusChar = worktreeChar
            }

            let kind = FileStatusKind(rawValue: String(statusChar)) ?? .modified
            files.append(GitFileStatus(path: path, status: kind))
        }
        return files
    }

    private func parseLog(_ output: String) -> [GitCommitInfo] {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var commits: [GitCommitInfo] = []
        var i = 0
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        while i + 4 < lines.count {
            let hash = lines[i]
            let shortHash = lines[i + 1]
            let author = lines[i + 2]
            let dateStr = lines[i + 3]
            let message = lines[i + 4]
            let date = formatter.date(from: dateStr) ?? Date()

            commits.append(GitCommitInfo(
                id: hash,
                shortHash: shortHash,
                author: author,
                date: date,
                message: message
            ))
            i += 5
        }
        return commits
    }

    private func parseDiffTree(_ output: String) -> [GitFileStatus] {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var files: [GitFileStatus] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let statusStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let path = String(parts[1])
            // Handle rename/copy status codes like R100, C080
            let kindChar = statusStr.prefix(1)
            let kind = FileStatusKind(rawValue: String(kindChar)) ?? .modified
            files.append(GitFileStatus(path: path, status: kind))
        }
        return files
    }

    private func parseWorktreeList(_ output: String) -> [GitWorktreeInfo] {
        var worktrees: [GitWorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?
        var isBare = false

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            if line.hasPrefix("worktree ") {
                if let path = currentPath {
                    worktrees.append(GitWorktreeInfo(
                        path: path,
                        branch: currentBranch,
                        isBare: isBare
                    ))
                }
                currentPath = String(line.dropFirst("worktree ".count))
                currentBranch = nil
                isBare = false
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                currentBranch = ref.replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "bare" {
                isBare = true
            }
        }
        if let path = currentPath {
            worktrees.append(GitWorktreeInfo(
                path: path,
                branch: currentBranch,
                isBare: isBare
            ))
        }
        return worktrees
    }
}

public struct GitWorktreeInfo: Sendable {
    public let path: String
    public let branch: String?
    public let isBare: Bool
}

public enum GitError: Error, LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Git command failed: \(message)"
        }
    }
}
