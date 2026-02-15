import Foundation

@MainActor @Observable
final class PaneState: Identifiable {
    let id: UUID
    var showRightPanel: Bool
    var changedFileCount: Int
    var dropZone: DropZone = .none

    init(
        id: UUID = UUID(),
        showRightPanel: Bool = false,
        changedFileCount: Int = 0
    ) {
        self.id = id
        self.showRightPanel = showRightPanel
        self.changedFileCount = changedFileCount
    }
}
