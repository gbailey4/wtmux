import Foundation

@MainActor @Observable
final class WindowState: Identifiable {
    let id: UUID
    var name: String
    var columns: [WorktreeColumn]

    init(id: UUID = UUID(), name: String, columns: [WorktreeColumn]) {
        self.id = id
        self.name = name
        self.columns = columns.isEmpty ? [WorktreeColumn()] : columns
    }
}
