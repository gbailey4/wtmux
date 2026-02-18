import Foundation

/// Codable model for `.wtmux/config.json` stored in the managed repo.
public struct ProjectConfig: Codable, Sendable {
    public var filesToCopy: [String]
    public var setupCommands: [String]
    public var runConfigurations: [RunConfig]
    public var terminalStartCommand: String?
    public var projectName: String?
    public var defaultBranch: String?
    public var worktreeBasePath: String?

    public init(
        filesToCopy: [String] = [],
        setupCommands: [String] = [],
        runConfigurations: [RunConfig] = [],
        terminalStartCommand: String? = nil,
        projectName: String? = nil,
        defaultBranch: String? = nil,
        worktreeBasePath: String? = nil
    ) {
        self.filesToCopy = filesToCopy
        self.setupCommands = setupCommands
        self.runConfigurations = runConfigurations
        self.terminalStartCommand = terminalStartCommand
        self.projectName = projectName
        self.defaultBranch = defaultBranch
        self.worktreeBasePath = worktreeBasePath
    }

    // Custom decoding to accept both "filesToCopy" and legacy "envFilesToCopy" JSON keys.
    private enum CodingKeys: String, CodingKey {
        case filesToCopy, setupCommands, runConfigurations
        case terminalStartCommand, projectName, defaultBranch, worktreeBasePath
        case envFilesToCopy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.filesToCopy = (try? container.decode([String].self, forKey: .filesToCopy))
            ?? ((try? container.decode([String].self, forKey: .envFilesToCopy)) ?? [])
        self.setupCommands = try container.decodeIfPresent([String].self, forKey: .setupCommands) ?? []
        self.runConfigurations = try container.decodeIfPresent([RunConfig].self, forKey: .runConfigurations) ?? []
        self.terminalStartCommand = try container.decodeIfPresent(String.self, forKey: .terminalStartCommand)
        self.projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        self.defaultBranch = try container.decodeIfPresent(String.self, forKey: .defaultBranch)
        self.worktreeBasePath = try container.decodeIfPresent(String.self, forKey: .worktreeBasePath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filesToCopy, forKey: .filesToCopy)
        try container.encode(setupCommands, forKey: .setupCommands)
        try container.encode(runConfigurations, forKey: .runConfigurations)
        try container.encodeIfPresent(terminalStartCommand, forKey: .terminalStartCommand)
        try container.encodeIfPresent(projectName, forKey: .projectName)
        try container.encodeIfPresent(defaultBranch, forKey: .defaultBranch)
        try container.encodeIfPresent(worktreeBasePath, forKey: .worktreeBasePath)
    }

    public struct RunConfig: Codable, Sendable {
        public var name: String
        public var command: String
        public var port: Int?
        public var autoStart: Bool
        public var order: Int

        public init(
            name: String,
            command: String,
            port: Int? = nil,
            autoStart: Bool = false,
            order: Int = 0
        ) {
            self.name = name
            self.command = command
            self.port = port
            self.autoStart = autoStart
            self.order = order
        }
    }
}
