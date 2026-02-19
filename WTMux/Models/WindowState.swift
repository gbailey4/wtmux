import Foundation
import WTDiff

enum WindowTabKind {
    case worktrees
    case diff(worktreePath: String, branchName: String)
}

enum WindowExecutionStatus: Equatable {
    case idle, thinking, inputNeeded, error

    var priority: Int {
        switch self {
        case .idle: 0
        case .thinking: 1
        case .inputNeeded: 2
        case .error: 3
        }
    }
}

@MainActor @Observable
final class WindowState: Identifiable {
    let id: UUID
    var name: String
    var columns: [WorktreeColumn]
    var kind: WindowTabKind
    var diffFile: DiffFile?
    var diffSourceColumnID: UUID?

    init(id: UUID = UUID(), name: String, columns: [WorktreeColumn], kind: WindowTabKind = .worktrees) {
        self.id = id
        self.name = name
        self.kind = kind
        switch kind {
        case .worktrees:
            self.columns = columns.isEmpty ? [WorktreeColumn()] : columns
        case .diff:
            self.columns = []
        }
    }

    func aggregateExecutionStatus(claudeStatusManager: ClaudeStatusManager) -> WindowExecutionStatus {
        var highest = WindowExecutionStatus.idle
        for column in columns {
            guard let worktreeID = column.worktreeID else { continue }
            guard let status = claudeStatusManager.status(forColumn: column.id.uuidString, worktreePath: worktreeID) else { continue }
            let windowStatus = status.toWindowStatus()
            if windowStatus.priority > highest.priority {
                highest = windowStatus
            }
        }
        return highest
    }
}
