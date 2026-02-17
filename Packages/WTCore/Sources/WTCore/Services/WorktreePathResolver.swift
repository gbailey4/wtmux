import Foundation

/// Resolves a branch name to a flat folder name for worktree creation.
///
/// Strategy:
/// 1. Replace `/` with `-` (e.g. `feature/ssh` → `feature-ssh`)
/// 2. If that collides with an existing path, replace `/` with `--`
/// 3. If still colliding, append `-2`, `-3`, etc.
public enum WorktreePathResolver {

    /// Returns a full worktree path that doesn't collide with any path in `existingPaths`.
    /// - Parameters:
    ///   - basePath: The worktree base directory (e.g. `/Users/x/project-worktrees`)
    ///   - branchName: The git branch name (may contain `/`)
    ///   - existingPaths: Set of paths already in use by other worktrees
    /// - Returns: A unique absolute path for the new worktree
    public static func resolve(
        basePath: String,
        branchName: String,
        existingPaths: Set<String>
    ) -> String {
        let folderName = folderName(for: branchName, existingNames: existingPaths.compactMap { path in
            // Extract just the folder name relative to basePath
            guard path.hasPrefix(basePath + "/") else { return nil }
            return String(path.dropFirst(basePath.count + 1))
        })
        return "\(basePath)/\(folderName)"
    }

    /// Computes a flat folder name from a branch name, avoiding collisions.
    /// Visible for testing.
    public static func folderName(
        for branchName: String,
        existingNames: [String]
    ) -> String {
        // No slashes — use the branch name directly
        guard branchName.contains("/") else {
            return branchName
        }

        let existing = Set(existingNames)

        // Primary: replace / with -
        let primary = branchName.replacingOccurrences(of: "/", with: "-")
        if !existing.contains(primary) {
            return primary
        }

        // Fallback: replace / with --
        let safe = branchName.replacingOccurrences(of: "/", with: "--")
        if !existing.contains(safe) {
            return safe
        }

        // Last resort: append numeric suffix to the safe name
        var counter = 2
        while true {
            let candidate = "\(safe)-\(counter)"
            if !existing.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }
}
