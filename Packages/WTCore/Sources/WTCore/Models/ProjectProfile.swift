import Foundation
import SwiftData

@Model
public final class ProjectProfile {
    public var project: Project?

    public var envFilesToCopy: [String] = []
    public var setupCommands: [String] = []

    @Relationship(deleteRule: .cascade, inverse: \RunConfiguration.profile)
    public var runConfigurations: [RunConfiguration] = []

    public init() {}
}

@Model
public final class RunConfiguration {
    public var name: String
    public var command: String
    public var port: Int?
    public var autoStart: Bool
    public var order: Int
    public var profile: ProjectProfile?

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
