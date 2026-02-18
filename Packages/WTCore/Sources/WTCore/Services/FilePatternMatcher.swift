import Foundation

public enum FilePatternMatcher {

    /// Expands glob patterns against a repo directory, returning matched relative paths.
    ///
    /// Pattern types:
    /// - `*` patterns (e.g. `.env*`): lists entries in the pattern's parent directory
    ///   and matches each name with `fnmatch`.
    /// - Trailing `/` (e.g. `.claude/`): checks if the literal directory exists.
    /// - Literal paths (e.g. `config.json`): checks if the file/directory exists.
    public static func match(patterns: [String], in repoPath: String) -> [String] {
        let fm = FileManager.default
        var results: [String] = []

        for pattern in patterns {
            if pattern.contains("*") {
                // Glob pattern — split into parent dir + filename pattern
                let nsPattern = pattern as NSString
                let parentDir = nsPattern.deletingLastPathComponent
                let filePattern = nsPattern.lastPathComponent

                let searchDir: String
                if parentDir.isEmpty || parentDir == "." {
                    searchDir = repoPath
                } else {
                    searchDir = (repoPath as NSString).appendingPathComponent(parentDir)
                }

                let searchURL = URL(fileURLWithPath: searchDir)
                guard let entries = try? fm.contentsOfDirectory(
                    at: searchURL,
                    includingPropertiesForKeys: nil,
                    options: []
                ) else { continue }

                for entry in entries {
                    let name = entry.lastPathComponent
                    if fnmatch(filePattern, name, 0) == 0 {
                        let relativePath: String
                        if parentDir.isEmpty || parentDir == "." {
                            relativePath = name
                        } else {
                            relativePath = (parentDir as NSString).appendingPathComponent(name)
                        }
                        if !results.contains(relativePath) {
                            results.append(relativePath)
                        }
                    }
                }
            } else {
                // Literal path (may have trailing slash for directories)
                let cleaned = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
                let fullPath = (repoPath as NSString).appendingPathComponent(cleaned)
                if fm.fileExists(atPath: fullPath) {
                    let entry = pattern.hasSuffix("/") ? cleaned : cleaned
                    if !results.contains(entry) {
                        results.append(entry)
                    }
                }
            }
        }

        results.sort()
        return results
    }
}

// MARK: - Presets

public enum FilePreset: String, CaseIterable, Sendable, Identifiable {
    case envFiles
    case claudeCode
    case vscode
    case cursor

    public var id: String { rawValue }

    public var pattern: String {
        switch self {
        case .envFiles: ".env*"
        case .claudeCode: ".claude/"
        case .vscode: ".vscode/"
        case .cursor: ".cursorrules"
        }
    }

    public var displayName: String {
        switch self {
        case .envFiles: "Environment Files"
        case .claudeCode: "Claude Code"
        case .vscode: "VS Code"
        case .cursor: "Cursor Rules"
        }
    }

    /// Returns presets that have at least one match in the given repo.
    public static func detectPresets(in repoPath: String) -> [FilePreset] {
        allCases.filter { preset in
            !FilePatternMatcher.match(patterns: [preset.pattern], in: repoPath).isEmpty
        }
    }
}
