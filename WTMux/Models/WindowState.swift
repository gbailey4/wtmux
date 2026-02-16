import Foundation
import WTDiff

enum WindowTabKind {
    case worktrees
    case diff(worktreePath: String, branchName: String)
}

@MainActor @Observable
final class WindowState: Identifiable {
    let id: UUID
    var name: String
    var columns: [WorktreeColumn]
    var kind: WindowTabKind
    var diffFile: DiffFile?
    var diffSourcePaneID: UUID?

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
}
