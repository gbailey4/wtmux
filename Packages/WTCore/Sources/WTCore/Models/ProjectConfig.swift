import Foundation

/// Codable model for `.wteasy/config.json` stored in the managed repo.
public struct ProjectConfig: Codable, Sendable {
    public var envFilesToCopy: [String]
    public var setupCommands: [String]
    public var runConfigurations: [RunConfig]

    public init(
        envFilesToCopy: [String] = [],
        setupCommands: [String] = [],
        runConfigurations: [RunConfig] = []
    ) {
        self.envFilesToCopy = envFilesToCopy
        self.setupCommands = setupCommands
        self.runConfigurations = runConfigurations
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
