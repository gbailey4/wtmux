import Foundation
import MCP

@main
struct WTEasyMCPServer {
    static func main() async throws {
        let server = Server(
            name: "wteasy",
            version: "1.0.0",
            instructions: """
                WTEasy project configuration server. Use these tools to set up projects \
                for the WTEasy git worktree manager.

                Workflow:
                1. Call get_project_config to check current configuration
                2. Examine the project structure (package.json, Makefile, docker-compose.yml, etc.)
                3. Call configure_project with setup commands, run configurations, env files, etc.

                The configure_project tool writes .wteasy/config.json and automatically \
                imports the project into the WTEasy app via URL scheme. The project will \
                appear in the sidebar immediately (or WTEasy will launch if not running).
                """,
            capabilities: .init(tools: .init())
        )

        let handlers = ToolHandlers()
        await handlers.register(on: server)

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
