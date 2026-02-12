import Foundation

public final class ProfileApplicator: Sendable {
    private let configService = ConfigService()

    public init() {}

    /// Loads the project config from `.wteasy/config.json`.
    public func loadConfig(forRepo repoPath: String) async -> ProjectConfig? {
        await configService.readConfig(forRepo: repoPath)
    }

    /// Copies env files listed in the config from the main repo to a worktree directory.
    public func applyEnvFiles(
        config: ProjectConfig,
        repoPath: String,
        worktreePath: String
    ) {
        let fm = FileManager.default
        for envFile in config.envFilesToCopy {
            let source = URL(fileURLWithPath: repoPath)
                .appendingPathComponent(envFile)
            let destination = URL(fileURLWithPath: worktreePath)
                .appendingPathComponent(envFile)

            guard fm.fileExists(atPath: source.path) else { continue }

            // Create intermediate directories if the env file is nested
            let destDir = destination.deletingLastPathComponent()
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

            // Copy, overwriting if already present
            if fm.fileExists(atPath: destination.path) {
                try? fm.removeItem(at: destination)
            }
            try? fm.copyItem(at: source, to: destination)
        }
    }
}
