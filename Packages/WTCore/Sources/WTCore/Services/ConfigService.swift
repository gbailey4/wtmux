import Foundation

public actor ConfigService {
    private static let configDir = ".wteasy"
    private static let configFile = "config.json"

    public init() {}

    /// Reads `.wteasy/config.json` from the given repo path.
    public func readConfig(forRepo repoPath: String) -> ProjectConfig? {
        let url = configFileURL(forRepo: repoPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(ProjectConfig.self, from: data)
    }

    /// Writes `.wteasy/config.json` into the given repo path, creating the directory if needed.
    public func writeConfig(_ config: ProjectConfig, forRepo repoPath: String) throws {
        let dirURL = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(Self.configDir)

        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let fileURL = dirURL.appendingPathComponent(Self.configFile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Ensures `.wteasy` is listed in the repo's `.gitignore`.
    public func ensureGitignore(forRepo repoPath: String) throws {
        let gitignoreURL = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".gitignore")

        var contents = ""
        if FileManager.default.fileExists(atPath: gitignoreURL.path) {
            contents = try String(contentsOf: gitignoreURL, encoding: .utf8)
        }

        let lines = contents.components(separatedBy: .newlines)
        let alreadyPresent = lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed == ".wteasy" || trimmed == ".wteasy/"
        }

        if !alreadyPresent {
            let suffix = contents.hasSuffix("\n") ? "" : "\n"
            contents += "\(suffix).wteasy\n"
            try contents.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        }
    }

    private func configFileURL(forRepo repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath)
            .appendingPathComponent(Self.configDir)
            .appendingPathComponent(Self.configFile)
    }
}
