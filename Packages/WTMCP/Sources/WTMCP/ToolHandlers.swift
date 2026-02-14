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
        [analyzeProjectTool, configureProjectTool, getProjectConfigTool]
    }

    private var configureProjectTool: Tool {
        Tool(
            name: "configure_project",
            description: """
                Configure a project for WTMux by writing .wtmux/config.json \
                and importing it into the app. Provide setup commands (e.g. npm install), \
                run configurations (dev servers, watchers), env files to copy between \
                worktrees, and an optional terminal start command. The project will \
                automatically appear in WTMux's sidebar.
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
                                        "Whether this is a default runner (included in Start Default and auto-launched when the runner panel opens). Optional runners (false) must be started individually."
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
                    "startClaudeInTerminals": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, automatically start Claude Code in new terminal tabs. Sets terminalStartCommand to 'claude'."
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
                Read the current .wtmux/config.json for a project. Returns the \
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

    private var analyzeProjectTool: Tool {
        Tool(
            name: "analyze_project",
            description: """
                Scan a git repository to detect its project structure: env files, \
                package manager, scripts (with categories), and default branch. \
                Returns a structured analysis to present to the user before configuring.
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
        case "analyze_project":
            return handleAnalyzeProject(params.arguments)
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

    // MARK: - analyze_project

    private func handleAnalyzeProject(_ arguments: [String: Value]?) -> CallTool.Result {
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

        let analysis = ProjectAnalyzer.analyze(repoPath: repoPath)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(analysis),
              let json = String(data: data, encoding: .utf8) else {
            return .init(content: [.text("Failed to serialize analysis result")], isError: true)
        }

        return .init(content: [.text(json)])
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
        let terminalStartCommand: String? = {
            if arguments?["startClaudeInTerminals"]?.boolValue == true {
                return "claude"
            }
            return arguments?["terminalStartCommand"]?.stringValue
        }()
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

        let gitignoreAdded: Bool
        do {
            try await configService.writeConfig(config, forRepo: repoPath)
            gitignoreAdded = try await configService.ensureGitignore(forRepo: repoPath)
        } catch {
            return .init(
                content: [.text("Failed to write config: \(error.localizedDescription)")],
                isError: true
            )
        }

        // Notify the running WTMux app to import the project via
        // DistributedNotificationCenter (cross-process, no window side-effects).
        // Pass the config inline so the app doesn't need to read config.json.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var userInfo: [String: String] = [:]
        if let data = try? encoder.encode(config),
           let json = String(data: data, encoding: .utf8) {
            userInfo["config"] = json
        }
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.grahampark.wtmux.importProject"),
            object: repoPath,
            userInfo: userInfo,
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
                let autoStr = rc.autoStart ? " [default]" : " [optional]"
                summary += "    \(rc.name): \(rc.command)\(portStr)\(autoStr)\n"
            }
        }
        if let cmd = terminalStartCommand {
            summary += "- Terminal start command: \(cmd)\n"
        }
        let gitignoreNote = gitignoreAdded
            ? "Added .wtmux to .gitignore."
            : ".wtmux was already in .gitignore."
        summary += "\n.wtmux/config.json written and project imported into WTMux. \(gitignoreNote)"

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
                "No .wtmux/config.json found at \(repoPath). Project is not yet configured for WTMux."
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
