import Testing
import Foundation
@testable import WTGit
import WTTransport

// MARK: - Mock Transport

/// A mock transport that returns canned responses, allowing parser testing
/// without requiring a real git repository.
struct MockTransport: CommandTransport {
    var responses: [String: CommandResult] = [:]

    func execute(_ command: String, in directory: String?) async throws -> CommandResult {
        CommandResult(exitCode: 0, stdout: "", stderr: "")
    }

    func execute(_ arguments: [String], in directory: String?) async throws -> CommandResult {
        CommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}

// MARK: - GitWorktreeInfo

@Test func gitWorktreeInfoInit() {
    let info = GitWorktreeInfo(path: "/tmp/test", branch: "main", isBare: false)
    #expect(info.path == "/tmp/test")
    #expect(info.branch == "main")
}

// MARK: - parseStatus

@Test func parseStatusEmpty() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseStatus("")
    #expect(result.isEmpty)
}

@Test func parseStatusWhitespaceOnly() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseStatus("  \n  ")
    #expect(result.isEmpty)
}

@Test func parseStatusModifiedFile() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseStatus(" M src/main.swift\n")
    #expect(result.count == 1)
    #expect(result[0].path == "src/main.swift")
    #expect(result[0].status == .modified)
}

@Test func parseStatusStagedFile() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseStatus("A  src/new.swift\n")
    #expect(result.count == 1)
    #expect(result[0].path == "src/new.swift")
    #expect(result[0].status == .added)
}

@Test func parseStatusUntrackedFile() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseStatus("?? untracked.txt\n")
    #expect(result.count == 1)
    #expect(result[0].path == "untracked.txt")
    #expect(result[0].status == .untracked)
}

@Test func parseStatusDeletedFile() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseStatus("D  removed.swift\n")
    #expect(result.count == 1)
    #expect(result[0].path == "removed.swift")
    #expect(result[0].status == .deleted)
}

@Test func parseStatusMultipleFiles() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let output = """
     M src/app.swift
    A  src/new.swift
    ?? untracked.txt
    D  old.swift
    """
    let result = await git.parseStatus(output)
    #expect(result.count == 4)
    #expect(result[0].status == .modified)
    #expect(result[1].status == .added)
    #expect(result[2].status == .untracked)
    #expect(result[3].status == .deleted)
}

@Test func parseStatusStagedOverWorktree() async {
    // When both index and worktree show changes, index status wins
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseStatus("AM src/file.swift\n")
    #expect(result.count == 1)
    #expect(result[0].status == .added)
}

// MARK: - parseLog

@Test func parseLogEmpty() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseLog("")
    #expect(result.isEmpty)
}

@Test func parseLogSingleCommit() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let output = """
    abc123def456abc123def456abc123def456abc123
    abc123d
    Jane Doe
    2025-06-15T10:30:00+00:00
    Fix login bug
    """
    let result = await git.parseLog(output)
    #expect(result.count == 1)
    #expect(result[0].id == "abc123def456abc123def456abc123def456abc123")
    #expect(result[0].shortHash == "abc123d")
    #expect(result[0].author == "Jane Doe")
    #expect(result[0].message == "Fix login bug")
}

@Test func parseLogMultipleCommits() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let output = """
    aaaa
    aaa
    Alice
    2025-06-15T10:00:00+00:00
    First commit
    bbbb
    bbb
    Bob
    2025-06-14T09:00:00+00:00
    Second commit
    """
    let result = await git.parseLog(output)
    #expect(result.count == 2)
    #expect(result[0].author == "Alice")
    #expect(result[1].author == "Bob")
}

@Test func parseLogIgnoresTrailingPartialCommit() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    // Only 3 lines — not enough for a complete commit (needs 5)
    let output = """
    aaaa
    aaa
    Alice
    """
    let result = await git.parseLog(output)
    #expect(result.isEmpty)
}

// MARK: - parseDiffTree

@Test func parseDiffTreeEmpty() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseDiffTree("")
    #expect(result.isEmpty)
}

@Test func parseDiffTreeBasicChanges() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let output = """
    M\tsrc/main.swift
    A\tsrc/new.swift
    D\tsrc/old.swift
    """
    let result = await git.parseDiffTree(output)
    #expect(result.count == 3)
    #expect(result[0].path == "src/main.swift")
    #expect(result[0].status == .modified)
    #expect(result[1].status == .added)
    #expect(result[2].status == .deleted)
}

@Test func parseDiffTreeRenameStatus() async {
    // Rename shows as R100 (100% similarity)
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let output = "R100\told.swift\tnew.swift\n"
    // parseDiffTree only splits on first tab, so the path includes the old→new
    let result = await git.parseDiffTree(output)
    #expect(result.count == 1)
    #expect(result[0].status == .renamed)
}

// MARK: - parseWorktreeList

@Test func parseWorktreeListEmpty() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let result = await git.parseWorktreeList("")
    #expect(result.isEmpty)
}

@Test func parseWorktreeListSingleWorktree() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let output = """
    worktree /Users/dev/project
    HEAD abc123
    branch refs/heads/main

    """
    let result = await git.parseWorktreeList(output)
    #expect(result.count == 1)
    #expect(result[0].path == "/Users/dev/project")
    #expect(result[0].branch == "main")
    #expect(result[0].isBare == false)
}

@Test func parseWorktreeListBareRepo() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let output = """
    worktree /Users/dev/project.git
    HEAD abc123
    bare

    """
    let result = await git.parseWorktreeList(output)
    #expect(result.count == 1)
    #expect(result[0].isBare == true)
    #expect(result[0].branch == nil)
}

@Test func parseWorktreeListMultiple() async {
    let git = GitService(transport: MockTransport(), repoPath: "/tmp")
    let output = """
    worktree /Users/dev/project.git
    HEAD abc123
    bare

    worktree /Users/dev/project-worktrees/feature-a
    HEAD def456
    branch refs/heads/feature-a

    worktree /Users/dev/project-worktrees/feature-b
    HEAD 789012
    branch refs/heads/feature-b

    """
    let result = await git.parseWorktreeList(output)
    #expect(result.count == 3)
    #expect(result[0].isBare == true)
    #expect(result[1].branch == "feature-a")
    #expect(result[2].branch == "feature-b")
}
