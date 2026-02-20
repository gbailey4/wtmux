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
    var panes: [WorktreePane]
    var kind: WindowTabKind
    var diffFile: DiffFile?
    var diffSourcePaneID: UUID?

    init(id: UUID = UUID(), name: String, panes: [WorktreePane], kind: WindowTabKind = .worktrees) {
        self.id = id
        self.name = name
        self.kind = kind
        switch kind {
        case .worktrees:
            self.panes = panes.isEmpty ? [WorktreePane()] : panes
        case .diff:
            self.panes = []
        }
    }

    func aggregateExecutionStatus(claudeStatusManager: ClaudeStatusManager) -> WindowExecutionStatus {
        var highest = WindowExecutionStatus.idle
        for pane in panes {
            guard let worktreeID = pane.worktreeID else { continue }
            guard let status = claudeStatusManager.status(forPane: pane.id.uuidString, worktreePath: worktreeID) else { continue }
            let windowStatus = status.toWindowStatus()
            if windowStatus.priority > highest.priority {
                highest = windowStatus
            }
        }
        return highest
    }
}
