import Foundation

@MainActor @Observable
final class WorktreeColumn: Identifiable {
    let id: UUID
    var worktreeID: String?
    var showRunnerPanel: Bool
    var showRightPanel: Bool
    var changedFileCount: Int
    var dropZone: DropZone = .none

    init(
        id: UUID = UUID(),
        worktreeID: String? = nil,
        showRunnerPanel: Bool = false,
        showRightPanel: Bool = false,
        changedFileCount: Int = 0
    ) {
        self.id = id
        self.worktreeID = worktreeID
        self.showRunnerPanel = showRunnerPanel
        self.showRightPanel = showRightPanel
        self.changedFileCount = changedFileCount
    }
}
