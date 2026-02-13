import Foundation
import os.log

private let logger = Logger(subsystem: "com.wteasy", category: "ProfileApplicator")

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

            guard fm.fileExists(atPath: source.path) else {
                logger.warning("Env file not found at source, skipping: \(envFile)")
                continue
            }

            // Create intermediate directories if the env file is nested
            let destDir = destination.deletingLastPathComponent()
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create directory for env file '\(envFile)': \(error.localizedDescription)")
                continue
            }

            // Copy, overwriting if already present
            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: source, to: destination)
            } catch {
                logger.error("Failed to copy env file '\(envFile)': \(error.localizedDescription)")
            }
        }
    }
}
