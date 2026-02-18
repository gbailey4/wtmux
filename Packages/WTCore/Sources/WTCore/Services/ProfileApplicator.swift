import Foundation
import os.log

private let logger = Logger(subsystem: "com.wtmux", category: "ProfileApplicator")

public final class ProfileApplicator: Sendable {
    public init() {}

    /// Copies files matching the given patterns from the main repo to a worktree directory.
    /// Patterns are expanded via `FilePatternMatcher` before copying.
    public func copyFiles(
        patterns: [String],
        repoPath: String,
        worktreePath: String
    ) {
        let files = FilePatternMatcher.match(patterns: patterns, in: repoPath)
        let fm = FileManager.default

        for file in files {
            let source = URL(fileURLWithPath: repoPath)
                .appendingPathComponent(file)
            let destination = URL(fileURLWithPath: worktreePath)
                .appendingPathComponent(file)

            guard fm.fileExists(atPath: source.path) else {
                logger.warning("File not found at source, skipping: \(file)")
                continue
            }

            // Create intermediate directories if the file is nested
            let destDir = destination.deletingLastPathComponent()
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create directory for '\(file)': \(error.localizedDescription)")
                continue
            }

            // Copy, overwriting if already present
            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: source, to: destination)
            } catch {
                logger.error("Failed to copy '\(file)': \(error.localizedDescription)")
            }
        }
    }
}
