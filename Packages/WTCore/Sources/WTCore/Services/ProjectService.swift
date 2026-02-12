import Foundation
import SwiftData

@Observable
public final class ProjectService: @unchecked Sendable {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchProjects() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor)
    }

    public func addProject(_ project: Project) {
        modelContext.insert(project)
        try? modelContext.save()
    }

    public func deleteProject(_ project: Project) {
        modelContext.delete(project)
        try? modelContext.save()
    }
}
