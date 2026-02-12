import Foundation
import SwiftData

@Model
public final class Project {
    public var name: String
    public var repoPath: String
    public var defaultBranch: String
    public var worktreeBasePath: String

    // SSH/Remote fields (nil for local projects)
    public var sshHost: String?
    public var sshUser: String?
    public var sshPort: Int?
    public var remoteRepoPath: String?
    public var remoteWorktreeBasePath: String?

    @Relationship(deleteRule: .cascade, inverse: \Worktree.project)
    public var worktrees: [Worktree] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectProfile.project)
    public var profile: ProjectProfile?

    public var isRemote: Bool {
        sshHost != nil
    }

    public var createdAt: Date

    public init(
        name: String,
        repoPath: String,
        defaultBranch: String = "main",
        worktreeBasePath: String = ""
    ) {
        self.name = name
        self.repoPath = repoPath
        self.defaultBranch = defaultBranch
        self.worktreeBasePath = worktreeBasePath
        self.createdAt = Date()
    }
}
