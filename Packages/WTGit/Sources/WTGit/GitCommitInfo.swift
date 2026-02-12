import Foundation

public struct GitCommitInfo: Sendable, Identifiable {
    public let id: String
    public let shortHash: String
    public let author: String
    public let date: Date
    public let message: String

    public init(id: String, shortHash: String, author: String, date: Date, message: String) {
        self.id = id
        self.shortHash = shortHash
        self.author = author
        self.date = date
        self.message = message
    }
}
