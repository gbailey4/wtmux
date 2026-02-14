import Foundation
import MCP

@main
struct WTMuxMCPServer {
    static func main() async throws {
        let server = Server(
            name: "wtmux",
            version: "1.0.0",
            instructions: """
                WTMux project configuration server. Use these tools to set up projects \
                for the WTMux git worktree manager.

                ## Workflow

                Follow this conversational flow — never skip straight to configure_project:

                1. **Analyze** — Call `analyze_project` with the repo path. This scans for \
                env files, package manager, scripts, and default branch.

                2. **Present & Ask** — Show the analysis results to the user, grouped clearly:
                   - **Env files** found on disk (ask if any should be removed or if others are missing)
                   - **Package manager** and setup command (ask if correct)
                   - **Runners** grouped by category:
                     • `devServer` scripts are suggested as **default** runners (autoStart: true)
                     • `build`, `test`, `lint`, and `other` scripts are shown but NOT automatically \
                       included as runners — ask the user which (if any) they want added as optional runners
                     • Not every script needs to be a runner. Let the user decide.
                   - **Default branch** (ask if correct)
                   - **Terminal start command** (ask if they want one, e.g. `claude`)

                3. **Refine** — Iterate on user feedback: add/remove runners, change default \
                vs optional, adjust ports, add custom runners not in package.json, etc.

                4. **Configure** — Once the user confirms, call `configure_project` with the \
                finalized settings.

                ## Rules

                - The `analyze_project` results are authoritative for env files — NEVER guess \
                env files by checking git remote, git ls-files, .gitignore, or any other means.
                - ALWAYS present findings to the user before calling `configure_project`. \
                Never configure without user review.
                - If the project already has a `.wtmux/config.json` (returned in the analysis \
                as `existingConfig`), show what's currently configured and ask what they'd like \
                to change rather than starting from scratch.
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
