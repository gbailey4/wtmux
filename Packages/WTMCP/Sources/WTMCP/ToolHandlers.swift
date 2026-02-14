import Foundation
import MCP
import WTCore

struct ToolHandlers: Sendable {
    private let configService = ConfigService()

    func register(on server: Server) async {
        await server.withMethodHandler(ListTools.self) { [self] _ in
            ListTools.Result(tools: self.toolDefinitions)
        }

        await server.withMethodHandler(CallTool.self) { [self] params in
            await self.handleCall(params)
        }
    }

    // MARK: - Tool Definitions

    private var toolDefinitions: [Tool] {
        [configureProjectTool, getProjectConfigTool]
    }

    private var configureProjectTool: Tool {
        Tool(
            name: "configure_project",
            description: """
                Configure a project for WTEasy by writing .wteasy/config.json \
                and importing it into the app. Provide setup commands (e.g. npm install), \
                run configurations (dev servers, watchers), env files to copy between \
                worktrees, and an optional terminal start command. The project will \
                automatically appear in WTEasy's sidebar.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "repoPath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the git repository root"),
                    ]),
                    "envFilesToCopy": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Relative paths to env files to copy to new worktrees (e.g. .env, .env.local). "
                            + "IMPORTANT: Only include files that actually exist on the local filesystem. "
                            + "Do NOT check git remote, git ls-files, or .gitignore to guess env file names. "
                            + "If you haven't confirmed a file exists locally, do not include it."
                        ),
                    ]),
                    "setupCommands": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Commands to run when setting up a new worktree (e.g. npm install, bundle install)"
                        ),
                    ]),
                    "runConfigurations": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "name": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "Display name for this runner (e.g. 'Dev Server', 'Tailwind')"
                                    ),
                                ]),
                                "command": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "Shell command to run (e.g. 'npm run dev', 'cargo watch')"
                                    ),
                                ]),
                                "port": .object([
                                    "type": .string("integer"),
                                    "description": .string(
                                        "Port number this service listens on, if any"
                                    ),
                                ]),
                                "autoStart": .object([
                                    "type": .string("boolean"),
                                    "description": .string(
                                        "Whether to start automatically when the worktree is opened"
                                    ),
                                ]),
                                "order": .object([
                                    "type": .string("integer"),
                                    "description": .string(
                                        "Sort order for display (lower numbers appear first)"
                                    ),
                                ]),
                            ]),
                            "required": .array([.string("name"), .string("command")]),
                        ]),
                        "description": .string("Dev server and process runner configurations"),
                    ]),
                    "terminalStartCommand": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Command to run when opening a new terminal in a worktree"
                        ),
                    ]),
                    "projectName": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Display name for the project (defaults to repo directory name)"
                        ),
                    ]),
                    "defaultBranch": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Default branch name (defaults to 'main')"
                        ),
                    ]),
                    "worktreeBasePath": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Directory where worktrees will be created (defaults to '<repoPath>-worktrees')"
                        ),
                    ]),
                ]),
                "required": .array([.string("repoPath")]),
            ])
        )
    }

    private var getProjectConfigTool: Tool {
        Tool(
            name: "get_project_config",
            description: """
                Read the current .wteasy/config.json for a project. Returns the \
                configuration if it exists, or a message indicating the project is not \
                yet configured.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "repoPath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the git repository root"),
                    ])
                ]),
                "required": .array([.string("repoPath")]),
            ])
        )
    }

    // MARK: - Call Dispatch

    private func handleCall(_ params: CallTool.Parameters) async -> CallTool.Result {
        switch params.name {
        case "configure_project":
            return await handleConfigureProject(params.arguments)
        case "get_project_config":
            return await handleGetProjectConfig(params.arguments)
        default:
            return CallTool.Result(
                content: [.text("Unknown tool: \(params.name)")],
                isError: true
            )
        }
    }

    // MARK: - configure_project

    private func handleConfigureProject(_ arguments: [String: Value]?) async -> CallTool.Result {
        guard let repoPath = arguments?["repoPath"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: repoPath")], isError: true)
        }

        guard repoPath.hasPrefix("/") else {
            return .init(content: [.text("repoPath must be an absolute path")], isError: true)
        }

        let gitDir = URL(fileURLWithPath: repoPath).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            return .init(
                content: [.text("No .git directory found at \(repoPath). Is this a git repository?")],
                isError: true
            )
        }

        let envFiles = arguments?["envFilesToCopy"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let setupCommands = arguments?["setupCommands"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let terminalStartCommand = arguments?["terminalStartCommand"]?.stringValue
        let projectName = arguments?["projectName"]?.stringValue
        let defaultBranch = arguments?["defaultBranch"]?.stringValue
        let worktreeBasePath = arguments?["worktreeBasePath"]?.stringValue

        var runConfigs: [ProjectConfig.RunConfig] = []
        if let runConfigValues = arguments?["runConfigurations"]?.arrayValue {
            for (index, value) in runConfigValues.enumerated() {
                guard let obj = value.objectValue,
                      let name = obj["name"]?.stringValue,
                      let command = obj["command"]?.stringValue else {
                    continue
                }
                let port = obj["port"]?.intValue
                let autoStart = obj["autoStart"]?.boolValue ?? false
                let order = obj["order"]?.intValue ?? index

                if let port, (port < 1 || port > 65535) {
                    return .init(
                        content: [.text("Invalid port \(port) for '\(name)'. Must be 1-65535.")],
                        isError: true
                    )
                }

                runConfigs.append(ProjectConfig.RunConfig(
                    name: name,
                    command: command,
                    port: port,
                    autoStart: autoStart,
                    order: order
                ))
            }
        }

        let config = ProjectConfig(
            envFilesToCopy: envFiles,
            setupCommands: setupCommands,
            runConfigurations: runConfigs,
            terminalStartCommand: terminalStartCommand,
            projectName: projectName,
            defaultBranch: defaultBranch,
            worktreeBasePath: worktreeBasePath
        )

        do {
            try await configService.writeConfig(config, forRepo: repoPath)
            try await configService.ensureGitignore(forRepo: repoPath)
        } catch {
            return .init(
                content: [.text("Failed to write config: \(error.localizedDescription)")],
                isError: true
            )
        }

        // Notify the running WTEasy app to import the project via
        // DistributedNotificationCenter (cross-process, no window side-effects).
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.grahampark.wteasy.importProject"),
            object: repoPath,
            userInfo: nil,
            deliverImmediately: true
        )

        var summary = "Configured \(repoPath):\n"
        if !envFiles.isEmpty {
            summary += "- Env files: \(envFiles.joined(separator: ", "))\n"
        }
        if !setupCommands.isEmpty {
            summary += "- Setup commands: \(setupCommands.count)\n"
            for cmd in setupCommands {
                summary += "    \(cmd)\n"
            }
        }
        if !runConfigs.isEmpty {
            summary += "- Run configurations: \(runConfigs.count)\n"
            for rc in runConfigs {
                let portStr = rc.port.map { " (port \($0))" } ?? ""
                let autoStr = rc.autoStart ? " [auto-start]" : ""
                summary += "    \(rc.name): \(rc.command)\(portStr)\(autoStr)\n"
            }
        }
        if let cmd = terminalStartCommand {
            summary += "- Terminal start command: \(cmd)\n"
        }
        summary += "\n.wteasy/config.json written, .gitignore updated, and project imported into WTEasy."

        return .init(content: [.text(summary)])
    }

    // MARK: - get_project_config

    private func handleGetProjectConfig(_ arguments: [String: Value]?) async -> CallTool.Result {
        guard let repoPath = arguments?["repoPath"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: repoPath")], isError: true)
        }

        guard repoPath.hasPrefix("/") else {
            return .init(content: [.text("repoPath must be an absolute path")], isError: true)
        }

        let config = await configService.readConfig(forRepo: repoPath)

        guard let config else {
            return .init(content: [.text(
                "No .wteasy/config.json found at \(repoPath). Project is not yet configured for WTEasy."
            )])
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(config),
              let json = String(data: data, encoding: .utf8) else {
            return .init(content: [.text("Failed to serialize config")], isError: true)
        }

        return .init(content: [.text(json)])
    }
}
