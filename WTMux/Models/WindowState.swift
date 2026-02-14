import Foundation

@MainActor @Observable
final class WindowState: Identifiable {
    let id: UUID
    var name: String
    var panes: [PaneState]

    init(id: UUID = UUID(), name: String, panes: [PaneState]) {
        self.id = id
        self.name = name
        self.panes = panes.isEmpty ? [PaneState()] : panes
    }
}
