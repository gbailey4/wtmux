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
        guard let entries = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // Also check hidden .env* files explicitly at this level
        if let allEntries = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) {
            for entry in allEntries {
                let name = entry.lastPathComponent
                if isEnvFile(name) {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: entry.path, isDirectory: &isDir), !isDir.boolValue {
                        let relativePath = entry.path.replacingOccurrences(
                            of: rootURL.path + "/", with: ""
                        )
                        if !results.contains(relativePath) {
                            results.append(relativePath)
                        }
                    }
                }
            }
        }

        // Recurse into non-skipped directories
        for entry in entries {
            let name = entry.lastPathComponent
            guard !skipDirectories.contains(name) else { continue }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                scanDirectory(entry, relativeTo: rootURL, depth: depth + 1, results: &results)
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
