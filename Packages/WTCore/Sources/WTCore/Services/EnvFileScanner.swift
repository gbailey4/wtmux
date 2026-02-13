import Foundation

public enum EnvFileScanner {
    private static let skipDirectories: Set<String> = [
        "node_modules", ".git", "vendor", ".build",
        "DerivedData", ".svn", ".hg", "Pods", "Carthage",
        ".swiftpm", "build", "dist", ".next", ".nuxt",
    ]

    private static let maxDepth = 5

    /// Scans the repo for env files recursively, returning paths relative to the repo root.
    /// Matches `.env*` and `*.env` patterns.
    public static func scan(repoPath: String) -> [String] {
        let repoURL = URL(fileURLWithPath: repoPath)
        var results: [String] = []
        scanDirectory(repoURL, relativeTo: repoURL, depth: 0, results: &results)
        results.sort()
        return results
    }

    private static func scanDirectory(
        _ dirURL: URL,
        relativeTo rootURL: URL,
        depth: Int,
        results: inout [String]
    ) {
        guard depth <= maxDepth else { return }

        let fm = FileManager.default
        // Single directory listing that includes hidden files (needed for .env*)
        guard let entries = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }

        for entry in entries {
            let name = entry.lastPathComponent
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                // Recurse into non-skipped, non-hidden directories
                if !skipDirectories.contains(name) && !name.hasPrefix(".") {
                    scanDirectory(entry, relativeTo: rootURL, depth: depth + 1, results: &results)
                }
            } else if isEnvFile(name) {
                let relativePath = entry.path.replacingOccurrences(
                    of: rootURL.path + "/", with: ""
                )
                if !results.contains(relativePath) {
                    results.append(relativePath)
                }
            }
        }
    }

    private static func isEnvFile(_ name: String) -> Bool {
        // Matches .env, .env.local, .env.production, etc.
        if name.hasPrefix(".env") { return true }
        // Matches something.env
        if name.hasSuffix(".env") { return true }
        return false
    }
}
