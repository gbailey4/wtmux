import AppKit
import SwiftUI
import WTLLM
import WTTransport

// MARK: - Shared AI Analysis State

enum AIAnalysisState: Equatable {
    case idle
    case gatheringContext
    case analyzing
    case failed(message: String)
}

// MARK: - AI Analysis Manager

/// Reusable observable that drives the AI analysis workflow.
/// Used by both `AddProjectView` and `ProjectSettingsView`.
@MainActor @Observable
final class AIAnalysisManager {
    var state: AIAnalysisState = .idle
    var pendingAnalysis: ProjectAnalysis?
    var showAnalysisPreview = false

    func runAnalysis(apiKey: String, model: String, repoPath: String) {
        state = .gatheringContext
        Task {
            let provider = ClaudeProvider(apiKey: apiKey, model: model)
            let transport = LocalTransport()
            let service = AnalysisService(provider: provider, transport: transport)

            for await progress in await service.analyze(repoPath: repoPath) {
                switch progress {
                case .gatheringContext:
                    state = .gatheringContext
                case .analyzing:
                    state = .analyzing
                case .complete(let analysis):
                    state = .idle
                    pendingAnalysis = analysis
                    showAnalysisPreview = true
                case .failed(let error):
                    state = .failed(message: error.userDescription)
                }
            }
        }
    }

    func dismissPreview() {
        showAnalysisPreview = false
        pendingAnalysis = nil
    }
}

// MARK: - LLMError User Descriptions

extension LLMError {
    /// Human-readable description suitable for display in the UI.
    var userDescription: String {
        switch self {
        case .noAPIKey:
            "Invalid API key. Check Settings."
        case .networkError(let detail):
            "Network error: \(detail)"
        case .rateLimited:
            "Rate limited. Please try again in a moment."
        case .invalidResponse(let detail):
            "Unexpected response: \(detail)"
        case .timeout:
            "Request timed out. Try again."
        }
    }
}

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

    /// Opens an `NSOpenPanel` to select environment files, returning
    /// (newFiles, selectedFiles) as relative paths from `repoPath`.
    @MainActor
    static func browseForEnvFiles(repoPath: String, existing: [String]) -> (detected: [String], selected: [String]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Select environment files to copy to new worktrees"
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

// MARK: - Analysis → EditableRunConfig mapping

extension ProjectAnalysis {
    /// Maps the analysis result into editable run configurations.
    func toEditableRunConfigs() -> [EditableRunConfig] {
        runConfigurations.map { rc in
            EditableRunConfig(
                name: rc.name,
                command: rc.command,
                portString: rc.port.map(String.init) ?? "",
                autoStart: rc.autoStart
            )
        }
    }
}

