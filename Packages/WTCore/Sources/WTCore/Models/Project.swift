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

    // Appearance
    public var colorName: String?
    public var iconName: String?

    // Ordering
    public var sortOrder: Int = 0

    // Sidebar state
    public var isCollapsed: Bool = false

    // Claude configuration state
    public var needsClaudeConfig: Bool?

    @Relationship(deleteRule: .cascade, inverse: \Worktree.project)
    public var worktrees: [Worktree] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectProfile.project)
    public var profile: ProjectProfile?

    public var isRemote: Bool {
        sshHost != nil
    }

    public var resolvedIconName: String {
        iconName ?? (isRemote ? "globe" : "folder.fill")
    }

    public var createdAt: Date

    public static let colorPalette: [String] = [
        "blue", "green", "orange", "purple", "teal", "pink", "indigo", "cyan"
    ]

    public static let iconPalette: [String] = [
        "folder.fill",
        "chevron.left.forwardslash.chevron.right",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "cube.fill",
        "shippingbox.fill",
        "terminal.fill",
        "globe",
        "building.2.fill",
        "leaf.fill",
        "gamecontroller.fill",
        "book.fill",
        "paintbrush.fill",
        "gearshape.fill",
        "server.rack",
        "cpu.fill",
    ]

    public static func nextColorName(in modelContext: ModelContext) -> String {
        let count = (try? modelContext.fetchCount(FetchDescriptor<Project>())) ?? 0
        return colorPalette[count % colorPalette.count]
    }

    public static func nextSortOrder(in modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        let projects = (try? modelContext.fetch(descriptor)) ?? []
        return (projects.first?.sortOrder ?? -1) + 1
    }

    public init(
        name: String,
        repoPath: String,
        defaultBranch: String = "main",
        worktreeBasePath: String = "",
        colorName: String? = nil,
        iconName: String? = nil,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.repoPath = repoPath
        self.defaultBranch = defaultBranch
        self.worktreeBasePath = worktreeBasePath
        self.colorName = colorName
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
