import Foundation

@MainActor @Observable
final class WorktreeColumn: Identifiable {
    let id: UUID
    var worktreeID: String?
    var panes: [PaneState]
    var showRunnerPanel: Bool
    var dropZone: DropZone = .none

    init(
        id: UUID = UUID(),
        worktreeID: String? = nil,
        panes: [PaneState] = [],
        showRunnerPanel: Bool = false
    ) {
        self.id = id
        self.worktreeID = worktreeID
        self.panes = panes.isEmpty ? [PaneState()] : panes
        self.showRunnerPanel = showRunnerPanel
    }
}
