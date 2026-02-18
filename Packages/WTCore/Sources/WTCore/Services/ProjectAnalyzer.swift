import Foundation

// MARK: - Result Types

public struct ProjectScanResult: Codable, Sendable {
    public var projectName: String
    public var envFiles: [String]
    public var packageManager: PackageManagerInfo?
    public var scripts: [ScriptInfo]
    public var defaultBranch: String?
    public var existingConfig: ProjectConfig?
}

public struct PackageManagerInfo: Codable, Sendable {
    public var name: String
    public var setupCommand: String
    public var lockFile: String?
}

public struct ScriptInfo: Codable, Sendable {
    public var name: String
    public var command: String
    public var runCommand: String
    public var category: ScriptCategory
}

public enum ScriptCategory: String, Codable, Sendable {
    case devServer
    case build
    case test
    case lint
    case other

    public var sortOrder: Int {
        switch self {
        case .devServer: 0
        case .build: 1
        case .test: 2
        case .lint: 3
        case .other: 4
        }
    }
}

// MARK: - Analyzer

public enum ProjectAnalyzer {
    public static func analyze(repoPath: String) -> ProjectScanResult {
        let repoURL = URL(fileURLWithPath: repoPath)
        let projectName = repoURL.lastPathComponent

        let envFiles = FilePatternMatcher.match(patterns: [".env*"], in: repoPath)
        let packageManager = detectPackageManager(repoPath: repoPath)
        let scripts = parseScripts(repoPath: repoPath, packageManager: packageManager)
        let defaultBranch = detectDefaultBranch(repoPath: repoPath)

        let existingConfig = readExistingConfig(repoPath: repoPath)

        return ProjectScanResult(
            projectName: projectName,
            envFiles: envFiles,
            packageManager: packageManager,
            scripts: scripts,
            defaultBranch: defaultBranch,
            existingConfig: existingConfig
        )
    }

    // MARK: - Package Manager Detection

    private struct PackageManagerCandidate {
        let manifestFile: String
        let lockFile: String?
        let name: String
        let setupCommand: String
    }

    private static func detectPackageManager(repoPath: String) -> PackageManagerInfo? {
        let fm = FileManager.default

        // Lock-file-specific checks first (most specific → least)
        let candidates: [PackageManagerCandidate] = [
            .init(manifestFile: "package.json", lockFile: "bun.lockb", name: "bun", setupCommand: "bun install"),
            .init(manifestFile: "package.json", lockFile: "bun.lock", name: "bun", setupCommand: "bun install"),
            .init(manifestFile: "package.json", lockFile: "pnpm-lock.yaml", name: "pnpm", setupCommand: "pnpm install"),
            .init(manifestFile: "package.json", lockFile: "yarn.lock", name: "yarn", setupCommand: "yarn install"),
            .init(manifestFile: "package.json", lockFile: nil, name: "npm", setupCommand: "npm install"),
            .init(manifestFile: "Gemfile", lockFile: nil, name: "bundler", setupCommand: "bundle install"),
            .init(manifestFile: "requirements.txt", lockFile: nil, name: "pip", setupCommand: "pip install -r requirements.txt"),
            .init(manifestFile: "pyproject.toml", lockFile: nil, name: "pip", setupCommand: "pip install -e ."),
            .init(manifestFile: "composer.json", lockFile: nil, name: "composer", setupCommand: "composer install"),
            .init(manifestFile: "Cargo.toml", lockFile: nil, name: "cargo", setupCommand: "cargo build"),
            .init(manifestFile: "go.mod", lockFile: nil, name: "go", setupCommand: "go mod download"),
            .init(manifestFile: "Package.swift", lockFile: nil, name: "swift", setupCommand: "swift package resolve"),
            .init(manifestFile: "Podfile", lockFile: nil, name: "cocoapods", setupCommand: "pod install"),
        ]

        for candidate in candidates {
            let manifestPath = (repoPath as NSString).appendingPathComponent(candidate.manifestFile)
            guard fm.fileExists(atPath: manifestPath) else { continue }

            if let lockFile = candidate.lockFile {
                let lockPath = (repoPath as NSString).appendingPathComponent(lockFile)
                guard fm.fileExists(atPath: lockPath) else { continue }
                return PackageManagerInfo(
                    name: candidate.name,
                    setupCommand: candidate.setupCommand,
                    lockFile: lockFile
                )
            } else {
                return PackageManagerInfo(
                    name: candidate.name,
                    setupCommand: candidate.setupCommand,
                    lockFile: nil
                )
            }
        }

        return nil
    }

    // MARK: - Script Parsing

    private static func parseScripts(repoPath: String, packageManager: PackageManagerInfo?) -> [ScriptInfo] {
        guard let pm = packageManager else { return [] }

        // Only parse package.json scripts for JS package managers
        let jsManagers: Set<String> = ["npm", "yarn", "pnpm", "bun"]
        guard jsManagers.contains(pm.name) else { return [] }

        let packageJsonPath = (repoPath as NSString).appendingPathComponent("package.json")
        guard let data = FileManager.default.contents(atPath: packageJsonPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: String] else {
            return []
        }

        let runPrefix: String
        switch pm.name {
        case "npm": runPrefix = "npm run"
        case "yarn": runPrefix = "yarn"
        case "pnpm": runPrefix = "pnpm run"
        case "bun": runPrefix = "bun run"
        default: runPrefix = "\(pm.name) run"
        }

        return scripts.map { name, command in
            let category = categorizeScript(name: name, command: command)
            return ScriptInfo(
                name: name,
                command: command,
                runCommand: "\(runPrefix) \(name)",
                category: category
            )
        }
        .sorted { a, b in
            if a.category.sortOrder != b.category.sortOrder {
                return a.category.sortOrder < b.category.sortOrder
            }
            return a.name < b.name
        }
    }

    private static func categorizeScript(name: String, command: String) -> ScriptCategory {
        let lowerName = name.lowercased()
        let lowerCommand = command.lowercased()

        // Dev server indicators
        let devNamePatterns = ["dev", "start", "serve", "watch"]
        let devCommandPatterns = ["vite", "next dev", "nodemon", "webpack serve", "webpack-dev-server",
                                  "ts-node-dev", "tsx watch", "nuxt dev", "remix dev", "astro dev"]
        if devNamePatterns.contains(where: { lowerName.contains($0) })
            || devCommandPatterns.contains(where: { lowerCommand.contains($0) }) {
            return .devServer
        }

        // Build indicators
        let buildPatterns = ["build", "compile", "bundle"]
        if buildPatterns.contains(where: { lowerName.contains($0) }) {
            return .build
        }

        // Test indicators
        let testPatterns = ["test", "e2e", "cypress", "vitest", "playwright"]
        if testPatterns.contains(where: { lowerName.contains($0) }) {
            return .test
        }

        // Lint indicators
        let lintPatterns = ["lint", "format", "check", "prettier", "typecheck", "type-check"]
        if lintPatterns.contains(where: { lowerName.contains($0) }) {
            return .lint
        }

        return .other
    }

    // MARK: - Default Branch Detection

    private static func detectDefaultBranch(repoPath: String) -> String? {
        // Try git symbolic-ref for the remote HEAD
        if let branch = runGit(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: repoPath) {
            // Returns e.g. "origin/main" — strip the remote prefix
            let components = branch.split(separator: "/", maxSplits: 1)
            if components.count == 2 {
                return String(components[1])
            }
            return branch
        }

        // Fall back to checking common branch names
        for name in ["main", "master"] {
            if runGit(["rev-parse", "--verify", name], in: repoPath) != nil {
                return name
            }
        }

        return nil
    }

    // MARK: - Existing Config

    private static func readExistingConfig(repoPath: String) -> ProjectConfig? {
        let url = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".wtmux")
            .appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProjectConfig.self, from: data)
    }

    // MARK: - Git Helpers

    private static func runGit(_ args: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
