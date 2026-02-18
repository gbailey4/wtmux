import SwiftUI
import WTCore
import WTGit
import WTTerminal
import WTTransport

/// Composes a worktree column: panes area + shared runner panel.
struct WorktreeColumnView: View {
    let column: WorktreeColumn
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let findWorktree: (String) -> Worktree?

    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id

    @State private var showSetupBanner = false
    @State private var showConfigPendingBanner = false

    private var worktree: Worktree? {
        guard let id = column.worktreeID else { return nil }
        return findWorktree(id)
    }

    private var hasRunConfigurations: Bool {
        !(worktree?.project?.profile?.runConfigurations.isEmpty ?? true)
    }

    private var isClaudeConfigRunning: Bool {
        guard let wt = worktree else { return false }
        return terminalSessionManager.sessions(forWorktree: wt.path).contains { session in
            session.initialCommand?.contains("configure_project") == true
        }
    }

    private var showRunnerPanelBinding: Binding<Bool> {
        Binding(
            get: { column.showRunnerPanel },
            set: { column.showRunnerPanel = $0 }
        )
    }

    private var currentTheme: TerminalTheme {
        TerminalThemes.theme(forId: terminalThemeId)
    }

    private var isFocused: Bool {
        guard let focusedPaneID = paneManager.focusedPaneID else { return false }
        return column.panes.contains { $0.id == focusedPaneID }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Configuration pending banner
            if let worktree, showConfigPendingBanner, worktree.project?.needsClaudeConfig == true, !isClaudeConfigRunning {
                configPendingBanner(worktree: worktree)
                Divider()
            }

            // Setup banner
            if let worktree, showSetupBanner,
               let commands = worktree.project?.profile?.setupCommands,
               !commands.filter({ !$0.isEmpty }).isEmpty {
                setupBanner(worktree: worktree, commands: commands)
                Divider()
            }

            // Panes area
            if column.panes.count > 1 {
                ColumnPanesView(
                    column: column,
                    paneManager: paneManager,
                    terminalSessionManager: terminalSessionManager,
                    findWorktree: findWorktree
                )
            } else if let pane = column.panes.first {
                PaneContentView(
                    pane: pane,
                    column: column,
                    paneManager: paneManager,
                    terminalSessionManager: terminalSessionManager,
                    findWorktree: findWorktree
                )
            }

            // Shared runner panel
            if let worktree {
                Divider()
                RunnerPanelView(
                    worktree: worktree,
                    terminalSessionManager: terminalSessionManager,
                    paneManager: paneManager,
                    showRunnerPanel: showRunnerPanelBinding,
                    isPaneFocused: isFocused
                )
                .frame(maxWidth: .infinity)
                .frame(
                    minHeight: column.showRunnerPanel ? 150 : nil,
                    idealHeight: column.showRunnerPanel ? 250 : nil,
                    maxHeight: column.showRunnerPanel ? 350 : nil
                )
            }
        }
        .background(currentTheme.background.toColor())
        .environment(\.colorScheme, currentTheme.isDark ? .dark : .light)
        .overlay(
            DropIndicatorView(zone: column.dropZone)
        )
        .task(id: column.worktreeID) {
            if let wt = worktree {
                showConfigPendingBanner = wt.project?.needsClaudeConfig == true
                showSetupBanner = wt.needsSetup == true
                // Auto-launch Claude config when the column first loads for a project that needs it
                if wt.project?.needsClaudeConfig == true, !isClaudeConfigRunning,
                   claudeIntegrationService.canUseClaudeConfig {
                    showConfigPendingBanner = false
                    openClaudeConfigTerminal(worktree: wt)
                }
            }
        }
        .onChange(of: worktree?.needsSetup) { _, newValue in
            if newValue == true {
                showSetupBanner = true
            }
        }
        .onChange(of: worktree?.project?.needsClaudeConfig) { _, newValue in
            if newValue == true {
                showConfigPendingBanner = true
            } else if newValue == false {
                showConfigPendingBanner = false
            }
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private func configPendingBanner(worktree: Worktree) -> some View {
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
                openClaudeConfigTerminal(worktree: worktree)
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
    private func setupBanner(worktree: Worktree, commands: [String]) -> some View {
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
                // Trigger setup via runner panel
                column.showRunnerPanel = true
                // The RunnerPanelView will handle setup when it initializes
                let runner = RunnerPanelView(
                    worktree: worktree,
                    terminalSessionManager: terminalSessionManager,
                    paneManager: paneManager,
                    showRunnerPanel: showRunnerPanelBinding,
                    isPaneFocused: isFocused
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

    private func openClaudeConfigTerminal(worktree: Worktree) {
        guard let repoPath = worktree.project?.repoPath,
              let pane = column.panes.first else { return }
        ClaudeConfigHelper.openConfigTerminal(
            terminalSessionManager: terminalSessionManager,
            paneId: pane.id.uuidString,
            worktreeId: worktree.path,
            workingDirectory: worktree.path,
            repoPath: repoPath
        )
    }
}
