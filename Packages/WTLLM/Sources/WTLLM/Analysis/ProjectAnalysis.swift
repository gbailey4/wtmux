import Foundation

public struct ProjectAnalysis: Codable, Sendable, Equatable {
    public var envFilesToCopy: [String]
    public var setupCommands: [String]
    public var runConfigurations: [RunConfigSuggestion]
    public var terminalStartCommand: String?
    public var projectType: String?
    public var notes: String?

    public init(
        envFilesToCopy: [String] = [],
        setupCommands: [String] = [],
        runConfigurations: [RunConfigSuggestion] = [],
        terminalStartCommand: String? = nil,
        projectType: String? = nil,
        notes: String? = nil
    ) {
        self.envFilesToCopy = envFilesToCopy
        self.setupCommands = setupCommands
        self.runConfigurations = runConfigurations
        self.terminalStartCommand = terminalStartCommand
        self.projectType = projectType
        self.notes = notes
    }

    public struct RunConfigSuggestion: Codable, Sendable, Equatable, Identifiable {
        public var id: String { name }
        public var name: String
        public var command: String
        public var port: Int?
        public var autoStart: Bool

        public init(name: String, command: String, port: Int? = nil, autoStart: Bool = false) {
            self.name = name
            self.command = command
            self.port = port
            self.autoStart = autoStart
        }
    }
}
