import SwiftUI
import WTCore
import WTTerminal

/// Shared header rendered once above all panes when every pane in the focused window
/// displays the same worktree. Shows project identity, Claude status, and config/setup banners.
struct SharedWorktreeHeaderView: View {
    let worktree: Worktree
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager

    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @State private var showConfigPendingBanner = false
    @State private var showSetupBanner = false

    private var worktreeId: String { worktree.path }

    private var isClaudeConfigRunning: Bool {
        terminalSessionManager.sessions(forWorktree: worktreeId).contains { session in
            session.initialCommand?.contains("configure_project") == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Config pending banner
            if showConfigPendingBanner, worktree.project?.needsClaudeConfig == true, !isClaudeConfigRunning {
                configPendingBanner
                Divider()
            }

            // Setup banner
            if showSetupBanner,
               let commands = worktree.project?.profile?.setupCommands,
               !commands.filter({ !$0.isEmpty }).isEmpty {
                setupBanner(commands: commands)
                Divider()
            }
        }
        .task(id: worktreeId) {
            showConfigPendingBanner = worktree.project?.needsClaudeConfig == true
            showSetupBanner = worktree.needsSetup == true
            // Auto-launch Claude config if needed
            if worktree.project?.needsClaudeConfig == true, !isClaudeConfigRunning,
               claudeIntegrationService.canUseClaudeConfig {
                showConfigPendingBanner = false
                openClaudeConfigTerminal()
            }
        }
        .onChange(of: worktree.needsSetup) { _, newValue in
            if newValue == true { showSetupBanner = true }
        }
        .onChange(of: worktree.project?.needsClaudeConfig) { _, newValue in
            if newValue == true {
                if !isClaudeConfigRunning, claudeIntegrationService.canUseClaudeConfig {
                    openClaudeConfigTerminal()
                } else {
                    showConfigPendingBanner = true
                }
            } else if newValue == false {
                showConfigPendingBanner = false
            }
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var configPendingBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Configuration Pending")
                    .font(.subheadline.bold())
                Text("Claude hasn't finished configuring this project yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Configure with Claude") {
                showConfigPendingBanner = false
                openClaudeConfigTerminal()
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!claudeIntegrationService.canUseClaudeConfig)
            Button {
                showConfigPendingBanner = false
                worktree.project?.needsClaudeConfig = false
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(10)
        .background(.orange.opacity(0.1))
    }

    @ViewBuilder
    private func setupBanner(commands: [String]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Setup Available")
                    .font(.subheadline.bold())
                Text(commands.count == 1 ? commands[0] : "\(commands.count) setup commands")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Run Setup") {
                showSetupBanner = false
                if let focusedPane = paneManager.focusedPane {
                    focusedPane.showRunnerPanel = true
                }
                let showRunnerBinding = Binding(
                    get: { paneManager.focusedPane?.showRunnerPanel ?? false },
                    set: { paneManager.focusedPane?.showRunnerPanel = $0 }
                )
                let runner = RunnerPanelView(
                    worktree: worktree,
                    terminalSessionManager: terminalSessionManager,
                    paneManager: paneManager,
                    showRunnerPanel: showRunnerBinding,
                    isPaneFocused: true
                )
                runner.runSetup()
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            Button {
                showSetupBanner = false
                worktree.needsSetup = false
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(10)
        .background(.blue.opacity(0.1))
    }

    private func openClaudeConfigTerminal() {
        guard let repoPath = worktree.project?.repoPath,
              let paneId = paneManager.focusedPane?.id.uuidString else { return }
        ClaudeConfigHelper.openConfigTerminal(
            terminalSessionManager: terminalSessionManager,
            paneId: paneId,
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            repoPath: repoPath
        )
    }
}
