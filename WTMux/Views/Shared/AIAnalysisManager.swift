import AppKit
import SwiftUI

// MARK: - File Browse Helpers

enum FileBrowseHelper {
    /// Opens an `NSOpenPanel` to select a directory for the worktree base path.
    @MainActor
    static func browseForDirectory(message: String, startingIn repoPath: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = message
        if !repoPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: repoPath).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    /// Opens an `NSOpenPanel` to select files or directories, returning
    /// (allPaths, newlySelected) as relative paths from `repoPath`.
    @MainActor
    static func browseForFiles(repoPath: String, existing: [String]) -> (detected: [String], selected: [String]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Select files or directories to copy to new worktrees"
        panel.directoryURL = URL(fileURLWithPath: repoPath)

        guard panel.runModal() == .OK else { return (existing, []) }

        var detected = existing
        var selected: [String] = []
        let repoURL = URL(fileURLWithPath: repoPath)

        for url in panel.urls {
            let relativePath: String
            if url.path.hasPrefix(repoURL.path) {
                let stripped = String(url.path.dropFirst(repoURL.path.count + 1))
                relativePath = stripped.isEmpty ? url.lastPathComponent : stripped
            } else {
                relativePath = url.lastPathComponent
            }
            if !detected.contains(relativePath) {
                detected.append(relativePath)
            }
            selected.append(relativePath)
        }

        return (detected, selected)
    }
}
