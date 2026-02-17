import WTTerminal

enum ClaudeConfigHelper {
    /// Returns the Claude CLI command string that triggers MCP-based project configuration.
    static func configCommand(repoPath: String) -> String {
        "claude \"Analyze the repo at \(repoPath) and use the wtmux MCP configure_project tool to configure it. Use \(repoPath) as the repoPath. Determine appropriate setup commands, run configurations (dev servers with ports), env files to copy between worktrees, and terminal start command. Before calling configure_project, present the proposed configuration to the user for review. If they give feedback, incorporate it and present the updated configuration again for approval. Only call configure_project once the user confirms.\""
    }

    /// Opens a terminal tab running the Claude config command and returns the session.
    @MainActor
    @discardableResult
    static func openConfigTerminal(
        terminalSessionManager: TerminalSessionManager,
        paneId: String,
        worktreeId: String,
        workingDirectory: String,
        repoPath: String
    ) -> TerminalSession {
        terminalSessionManager.createTab(
            forPane: paneId,
            worktreeId: worktreeId,
            workingDirectory: workingDirectory,
            initialCommand: configCommand(repoPath: repoPath)
        )
    }
}
