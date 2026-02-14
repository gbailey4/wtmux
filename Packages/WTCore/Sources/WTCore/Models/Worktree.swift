import Foundation
import SwiftData

public enum WorktreeStatus: String, Codable, Sendable {
    case creating
    case ready
    case active
    case archived
    case error
}

@Model
public final class Worktree {
    public var branchName: String
    public var path: String
    public var baseBranch: String
    public var statusRaw: String
    public var project: Project?
    public var createdAt: Date
    public var notes: String?
    public var needsSetup: Bool?
    public var sortOrder: Int = 0

    public var status: WorktreeStatus {
        get { WorktreeStatus(rawValue: statusRaw) ?? .error }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        branchName: String,
        path: String,
        baseBranch: String,
        status: WorktreeStatus = .creating,
        sortOrder: Int = 0
    ) {
        self.branchName = branchName
        self.path = path
        self.baseBranch = baseBranch
        self.statusRaw = status.rawValue
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.needsSetup = false
    }
}
