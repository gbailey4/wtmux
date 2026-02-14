import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.wtmux", category: "ProjectService")

// @unchecked Sendable: ProjectService is always created and used on @MainActor
// (via SwiftUI views with @Environment(\.modelContext)). @Observable does not
// support actor isolation directly, so we mark Sendable compliance manually.
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
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save after adding project '\(project.name)': \(error.localizedDescription)")
        }
    }

    public func deleteProject(_ project: Project) {
        modelContext.delete(project)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save after deleting project '\(project.name)': \(error.localizedDescription)")
        }
    }
}
