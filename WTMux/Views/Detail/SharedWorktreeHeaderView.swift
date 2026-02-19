import SwiftUI
import WTCore
import WTTerminal

/// Shared header rendered once above all columns when every column in the focused window
/// displays the same worktree. Shows project identity, Claude status, and config/setup banners.
struct SharedWorktreeHeaderView: View {
    let worktree: Worktree
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager

    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @Environment(ClaudeStatusManager.self) private var claudeStatusManager
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @Environment(ThemeManager.self) private var themeManager

    @State private var showConfigPendingBanner = false
    @State private var showSetupBanner = false

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

    private var worktreeId: String { worktree.path }

    private var isClaudeConfigRunning: Bool {
        terminalSessionManager.sessions(forWorktree: worktreeId).contains { session in
            session.initialCommand?.contains("configure_project") == true
        }
    }

    /// Aggregate Claude status across all columns showing this worktree.
    private var claudeStatus: ClaudeCodeStatus? {
        guard let window = paneManager.focusedWindow else { return nil }
        var best: ClaudeCodeStatus?
        for column in window.columns {
            if let status = claudeStatusManager.status(forColumn: column.id.uuidString, worktreePath: worktreeId) {
                if best == nil { best = status }
                else if status.priority > best!.priority { best = status }
            }
        }
        return best
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

            // Shared breadcrumb header
            HStack(spacing: 5) {
                if let project = worktree.project {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(projectColor(for: project))
                        .frame(width: 3, height: 12)
                    Image(systemName: project.resolvedIconName)
                        .foregroundStyle(projectColor(for: project))
                        .font(.caption)
                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("/")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(worktree.branchName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let status = claudeStatus {
                    claudeStatusBadge(status)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(currentTheme.chromeBackground.toColor())
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

    // MARK: - Claude Status Badge

    @ViewBuilder
    private func claudeStatusBadge(_ status: ClaudeCodeStatus) -> some View {
        switch status {
        case .idle:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
        case .thinking:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.purple)
                .symbolEffect(.pulse)
        case .working:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .needsAttention:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)
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
                if let col = paneManager.focusedColumn {
                    col.showRunnerPanel = true
                }
                let showRunnerBinding = Binding(
                    get: { paneManager.focusedColumn?.showRunnerPanel ?? false },
                    set: { paneManager.focusedColumn?.showRunnerPanel = $0 }
                )
                let runner = RunnerPanelView(
                    worktree: worktree,
                    terminalSessionManager: terminalSessionManager,
                    paneManager: paneManager,
                    showRunnerPanel: showRunnerBinding,
                    isColumnFocused: true
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
              let columnId = paneManager.focusedColumn?.id.uuidString else { return }
        ClaudeConfigHelper.openConfigTerminal(
            terminalSessionManager: terminalSessionManager,
            columnId: columnId,
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            repoPath: repoPath
        )
    }
}

// MARK: - ClaudeCodeStatus priority for aggregation

private extension ClaudeCodeStatus {
    var priority: Int {
        switch self {
        case .idle: 0
        case .done: 1
        case .thinking: 2
        case .working: 3
        case .needsAttention: 4
        }
    }
}
