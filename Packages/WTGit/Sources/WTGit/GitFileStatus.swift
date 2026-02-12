import Foundation

public enum FileStatusKind: String, Sendable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case unmodified = " "
}

public struct GitFileStatus: Sendable, Identifiable {
    public let id: String
    public let path: String
    public let status: FileStatusKind

    public init(path: String, status: FileStatusKind) {
        self.id = path
        self.path = path
        self.status = status
    }
}
