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
