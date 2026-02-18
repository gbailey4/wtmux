import Foundation

public enum PromptBuilder {
    public static let systemPrompt = """
        You are a developer tools assistant that analyzes project repositories to suggest \
        configuration for a worktree management tool. You will receive a directory tree \
        and the contents of key config files.

        Be precise and conservative:
        - Only suggest files/directories that actually exist (listed in the directory tree or referenced in configs)
        - Only suggest setup commands you are confident are correct for the project
        - Only suggest run configurations for scripts/commands you can see defined
        - For ports, only include a port number if you can determine it from the config
        - Set autoStart to true for default runners (included in batch start and auto-launched \
        when the runner panel opens). Set to false for optional runners that the user starts individually.

        Common patterns:
        - Node.js: look at package.json scripts for dev/start/build commands and the package manager lock file
        - Python: look at pyproject.toml, requirements.txt, Pipfile for dependency install commands
        - Rust: Cargo.toml for cargo run/build commands
        - Go: go.mod for go run/build commands
        - Docker: docker-compose.yml for service configurations
        - Monorepo: turbo.json/nx.json for workspace commands

        For terminalStartCommand, suggest a shell command that puts the user in a useful \
        starting state (e.g. activating a virtualenv, running a shell with the right env).
        Leave it null if a plain shell is fine.
        """

    public static func buildUserMessage(from context: ProjectContext) -> String {
        var message = "## Directory Tree\n\n```\n\(context.directoryTree)\n```\n\n"

        if !context.fileContents.isEmpty {
            message += "## Config Files\n\n"
            for (path, content) in context.fileContents {
                message += "### \(path)\n\n```\n\(content)\n```\n\n"
            }
        }

        message += """
            Analyze this project and call the `report_project_analysis` tool with your findings.
            """

        return message
    }

    public static func analysisToolDefinition() -> ToolDefinition {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "filesToCopy": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Glob patterns or paths for files/directories to copy to new worktrees (e.g. '.env*', '.claude/', '.vscode/')"
                ],
                "setupCommands": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Shell commands to run when setting up a new worktree (e.g. 'pnpm install', 'pip install -e .')"
                ],
                "runConfigurations": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": [
                                "type": "string",
                                "description": "Human-readable name for this run configuration"
                            ],
                            "command": [
                                "type": "string",
                                "description": "Shell command to execute"
                            ],
                            "port": [
                                "type": "integer",
                                "description": "Port number this command listens on, if applicable"
                            ],
                            "autoStart": [
                                "type": "boolean",
                                "description": "Whether this is a default runner (included in batch start and auto-launched when the runner panel opens). Optional runners (false) must be started individually."
                            ]
                        ],
                        "required": ["name", "command", "autoStart"]
                    ],
                    "description": "Suggested run configurations (dev servers, build watchers, etc.)"
                ],
                "terminalStartCommand": [
                    "type": "string",
                    "description": "Shell command to run when opening a terminal in a worktree (e.g. activating a virtualenv). Null if a plain shell is fine."
                ],
                "projectType": [
                    "type": "string",
                    "description": "Brief project type identifier (e.g. 'Next.js', 'Django + React', 'Rust CLI')"
                ],
                "notes": [
                    "type": "string",
                    "description": "Any additional insights about the project setup that might be useful"
                ]
            ],
            "required": ["filesToCopy", "setupCommands", "runConfigurations"]
        ]

        // Safe to force-try: the dictionary above is a hardcoded JSON-compatible literal.
        let schemaData = try! JSONSerialization.data(withJSONObject: schema)

        return ToolDefinition(
            name: "report_project_analysis",
            description: "Report the analysis of a project repository, including env files, setup commands, and run configurations.",
            inputSchemaJSON: schemaData
        )
    }
}
