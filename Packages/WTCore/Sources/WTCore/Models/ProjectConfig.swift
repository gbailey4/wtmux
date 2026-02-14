import Foundation

/// Codable model for `.wtmux/config.json` stored in the managed repo.
public struct ProjectConfig: Codable, Sendable {
    public var envFilesToCopy: [String]
    public var setupCommands: [String]
    public var runConfigurations: [RunConfig]
    public var terminalStartCommand: String?
    public var projectName: String?
    public var defaultBranch: String?
    public var worktreeBasePath: String?

    public init(
        envFilesToCopy: [String] = [],
        setupCommands: [String] = [],
        runConfigurations: [RunConfig] = [],
        terminalStartCommand: String? = nil,
        projectName: String? = nil,
        defaultBranch: String? = nil,
        worktreeBasePath: String? = nil
    ) {
        self.envFilesToCopy = envFilesToCopy
        self.setupCommands = setupCommands
        self.runConfigurations = runConfigurations
        self.terminalStartCommand = terminalStartCommand
        self.projectName = projectName
        self.defaultBranch = defaultBranch
        self.worktreeBasePath = worktreeBasePath
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
