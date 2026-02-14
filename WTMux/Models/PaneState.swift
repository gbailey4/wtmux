import Foundation

@MainActor @Observable
final class PaneState: Identifiable {
    let id: UUID
    var worktreeID: String?
    var showRightPanel: Bool
    var showRunnerPanel: Bool
    var changedFileCount: Int
    var dropZone: DropZone = .none

    init(
        id: UUID = UUID(),
        worktreeID: String? = nil,
        showRightPanel: Bool = false,
        showRunnerPanel: Bool = false,
        changedFileCount: Int = 0
    ) {
        self.id = id
        self.worktreeID = worktreeID
        self.showRightPanel = showRightPanel
        self.showRunnerPanel = showRunnerPanel
        self.changedFileCount = changedFileCount
    }
}
