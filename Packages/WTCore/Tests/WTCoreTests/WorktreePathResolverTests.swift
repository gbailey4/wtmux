import Testing
@testable import WTCore

@Suite("WorktreePathResolver")
struct WorktreePathResolverTests {

    // MARK: - folderName

    @Test func simpleNameNoSlashes() {
        let result = WorktreePathResolver.folderName(for: "my-branch", existingNames: [])
        #expect(result == "my-branch")
    }

    @Test func singleSlashFlattened() {
        let result = WorktreePathResolver.folderName(for: "feature/ssh", existingNames: [])
        #expect(result == "feature-ssh")
    }

    @Test func multipleSlashesFlattened() {
        let result = WorktreePathResolver.folderName(for: "feat/scope/thing", existingNames: [])
        #expect(result == "feat-scope-thing")
    }

    @Test func collisionFallsBackToDoubleDash() {
        // "feature-ssh" already exists as a folder, so "feature/ssh" should use "--"
        let result = WorktreePathResolver.folderName(
            for: "feature/ssh",
            existingNames: ["feature-ssh"]
        )
        #expect(result == "feature--ssh")
    }

    @Test func doubleCollisionFallsBackToNumericSuffix() {
        // Both "feature-ssh" and "feature--ssh" exist
        let result = WorktreePathResolver.folderName(
            for: "feature/ssh",
            existingNames: ["feature-ssh", "feature--ssh"]
        )
        #expect(result == "feature--ssh-2")
    }

    @Test func numericSuffixIncrementsUntilFree() {
        let result = WorktreePathResolver.folderName(
            for: "feature/ssh",
            existingNames: ["feature-ssh", "feature--ssh", "feature--ssh-2"]
        )
        #expect(result == "feature--ssh-3")
    }

    @Test func branchWithDashDoesNotCollideWithSlashBranch() {
        // "feature-ssh" exists; creating "feature-ssh" (no slash) should return it directly
        let result = WorktreePathResolver.folderName(for: "feature-ssh", existingNames: ["feature-ssh-other"])
        #expect(result == "feature-ssh")
    }

    // MARK: - resolve (full path)

    @Test func resolveProducesFullPath() {
        let result = WorktreePathResolver.resolve(
            basePath: "/home/user/project-worktrees",
            branchName: "feature/auth",
            existingPaths: Set()
        )
        #expect(result == "/home/user/project-worktrees/feature-auth")
    }

    @Test func resolveDetectsCollisionFromFullPaths() {
        let result = WorktreePathResolver.resolve(
            basePath: "/base",
            branchName: "feature/ssh",
            existingPaths: ["/base/feature-ssh"]
        )
        #expect(result == "/base/feature--ssh")
    }

    @Test func resolveIgnoresPathsOutsideBasePath() {
        // "/other/feature-ssh" shouldn't count as a collision for "/base"
        let result = WorktreePathResolver.resolve(
            basePath: "/base",
            branchName: "feature/ssh",
            existingPaths: ["/other/feature-ssh"]
        )
        #expect(result == "/base/feature-ssh")
    }
}
