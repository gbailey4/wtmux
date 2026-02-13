import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.wteasy", category: "ProjectImportService")

/// Creates or updates a SwiftData `Project` from a `ProjectConfig` and repo path.
@MainActor
public struct ProjectImportService {
    public init() {}

    /// Import a project from its config file. Creates a new project or updates an existing one.
    ///
    /// Matching strategy:
    /// 1. Exact `repoPath` match against existing projects.
    /// 2. If no exact match, check whether the incoming `repoPath` is a
    ///    subdirectory of any existing project's `worktreeBasePath`. This
    ///    handles the common case where the MCP `configure_project` tool is
    ///    invoked from within a worktree directory rather than the bare repo.
    public func importProject(
        repoPath: String,
        config: ProjectConfig,
        in modelContext: ModelContext
    ) {
        let name = config.projectName
            ?? URL(fileURLWithPath: repoPath).lastPathComponent
        let branch = config.defaultBranch ?? "main"
        let wtBase = config.worktreeBasePath ?? "\(repoPath)-worktrees"

        // 1. Check for existing project by exact repoPath
        let predicate = #Predicate<Project> { $0.repoPath == repoPath }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)
        var existing = try? modelContext.fetch(descriptor).first

        // 2. If no exact match, check if repoPath falls under any project's worktreeBasePath
        //    e.g., incoming "/repo-worktrees/feature" matches project with worktreeBasePath "/repo-worktrees"
        if existing == nil {
            let allDescriptor = FetchDescriptor<Project>()
            if let allProjects = try? modelContext.fetch(allDescriptor) {
                let normalizedPath = repoPath.hasSuffix("/") ? repoPath : repoPath + "/"
                existing = allProjects.first { project in
                    guard !project.worktreeBasePath.isEmpty else { return false }
                    let normalizedBase = project.worktreeBasePath.hasSuffix("/")
                        ? project.worktreeBasePath
                        : project.worktreeBasePath + "/"
                    return normalizedPath.hasPrefix(normalizedBase)
                }
            }
        }

        if let project = existing {
            // Update existing project profile — but preserve the user-chosen name
            if !project.worktreeBasePath.isEmpty {
                // Only update branch/base when the config provides explicit values
                if config.defaultBranch != nil {
                    project.defaultBranch = branch
                }
                if config.worktreeBasePath != nil {
                    project.worktreeBasePath = wtBase
                }
            } else {
                project.defaultBranch = branch
                project.worktreeBasePath = wtBase
            }

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

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save imported project at '\(repoPath)': \(error.localizedDescription)")
        }
    }
}
