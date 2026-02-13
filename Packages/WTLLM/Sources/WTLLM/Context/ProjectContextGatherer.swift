import Foundation
import WTTransport

public struct ProjectContext: Sendable {
    public let directoryTree: String
    public let fileContents: [(path: String, content: String)]

    public init(directoryTree: String, fileContents: [(path: String, content: String)]) {
        self.directoryTree = directoryTree
        self.fileContents = fileContents
    }
}

public actor ProjectContextGatherer {
    private let transport: any CommandTransport

    private static let excludedDirs = [
        "node_modules", ".git", "vendor", ".build", "DerivedData",
        "dist", ".next", ".nuxt", "__pycache__", ".venv", "venv",
        "target", "build", ".svelte-kit", ".output"
    ]

    private static let configFiles: [String] = [
        "package.json",
        "Makefile",
        "Justfile",
        "Dockerfile",
        "docker-compose.yml",
        "docker-compose.yaml",
        "pyproject.toml",
        "requirements.txt",
        "Pipfile",
        "Cargo.toml",
        "go.mod",
        "Gemfile",
        "mix.exs",
        ".env.example",
        ".env.sample",
        "turbo.json",
        "nx.json",
        "Procfile",
        "vite.config.ts",
        "vite.config.js",
        "next.config.ts",
        "next.config.js",
        "next.config.mjs",
        "nuxt.config.ts",
        "nuxt.config.js",
        "angular.json",
        "tsconfig.json",
        "Taskfile.yml",
    ]

    private static let maxTreeLines = 200
    private static let maxFileLines = 150

    public init(transport: any CommandTransport) {
        self.transport = transport
    }

    public func gather(repoPath: String) async throws -> ProjectContext {
        let tree = try await gatherDirectoryTree(repoPath: repoPath)
        let files = await gatherConfigFiles(repoPath: repoPath)
        return ProjectContext(directoryTree: tree, fileContents: files)
    }

    // MARK: - Directory Tree

    private func gatherDirectoryTree(repoPath: String) async throws -> String {
        let excludeArgs = Self.excludedDirs
            .flatMap { ["-not", "-path", "*/\($0)/*"] }

        let findArgs = ["find", ".", "-maxdepth", "3"] + excludeArgs + ["-print"]
        let result = try await transport.execute(findArgs, in: repoPath)

        let lines = result.stdout.components(separatedBy: "\n")
        let truncated = lines.prefix(Self.maxTreeLines)
        let tree = truncated.joined(separator: "\n")

        if lines.count > Self.maxTreeLines {
            return tree + "\n... (truncated, \(lines.count) total entries)"
        }
        return tree
    }

    // MARK: - Config Files

    private func gatherConfigFiles(repoPath: String) async -> [(path: String, content: String)] {
        var results: [(path: String, content: String)] = []

        for file in Self.configFiles {
            guard let content = await readFile(file, in: repoPath) else { continue }
            results.append((path: file, content: content))
        }

        return results
    }

    private func readFile(_ relativePath: String, in repoPath: String) async -> String? {
        let headArgs = ["head", "-n", "\(Self.maxFileLines)", relativePath]
        guard let result = try? await transport.execute(headArgs, in: repoPath),
              result.succeeded else {
            return nil
        }
        let content = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }
}
