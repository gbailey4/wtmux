import Foundation
import SwiftData

/// Creates or updates a SwiftData `Project` from a `ProjectConfig` and repo path.
@MainActor
public struct ProjectImportService {
    public init() {}

    /// Import a project from its config file. Creates a new project or updates an existing one.
    public func importProject(
        repoPath: String,
        config: ProjectConfig,
        in modelContext: ModelContext
    ) {
        let name = config.projectName
            ?? URL(fileURLWithPath: repoPath).lastPathComponent
        let branch = config.defaultBranch ?? "main"
        let wtBase = config.worktreeBasePath ?? "\(repoPath)-worktrees"

        // Check for existing project by repoPath
        let predicate = #Predicate<Project> { $0.repoPath == repoPath }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)
        let existing = try? modelContext.fetch(descriptor).first

        if let project = existing {
            // Update existing project
            project.name = name
            project.defaultBranch = branch
            project.worktreeBasePath = wtBase

            if let profile = project.profile {
                profile.envFilesToCopy = config.envFilesToCopy
                profile.setupCommands = config.setupCommands
                profile.terminalStartCommand = config.terminalStartCommand

                // Replace run configurations
                for rc in profile.runConfigurations {
                    modelContext.delete(rc)
                }
                profile.runConfigurations = []

                for (index, rc) in config.runConfigurations.enumerated() {
                    let runConfig = RunConfiguration(
                        name: rc.name,
                        command: rc.command,
                        port: rc.port,
                        autoStart: rc.autoStart,
                        order: rc.order != 0 ? rc.order : index
                    )
                    runConfig.profile = profile
                    profile.runConfigurations.append(runConfig)
                }
            }
        } else {
            // Create new project
            let project = Project(
                name: name,
                repoPath: repoPath,
                defaultBranch: branch,
                worktreeBasePath: wtBase
            )

            let profile = ProjectProfile()
            profile.envFilesToCopy = config.envFilesToCopy
            profile.setupCommands = config.setupCommands
            profile.terminalStartCommand = config.terminalStartCommand

            for (index, rc) in config.runConfigurations.enumerated() {
                let runConfig = RunConfiguration(
                    name: rc.name,
                    command: rc.command,
                    port: rc.port,
                    autoStart: rc.autoStart,
                    order: rc.order != 0 ? rc.order : index
                )
                runConfig.profile = profile
                profile.runConfigurations.append(runConfig)
            }

            profile.project = project
            project.profile = profile
            modelContext.insert(project)
        }

        try? modelContext.save()
    }
}
