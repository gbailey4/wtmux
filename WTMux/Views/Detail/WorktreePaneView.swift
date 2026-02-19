import SwiftUI
import WTCore
import WTGit
import WTTerminal
import WTTransport

/// Composes a worktree pane: unified header + terminal content + runner panel.
struct WorktreePaneView: View {
    let pane: WorktreePane
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let findWorktree: (String) -> Worktree?
    var isSharedLayout: Bool = false

    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @Environment(ThemeManager.self) private var themeManager

    @State private var showSetupBanner = false
    @State private var showConfigPendingBanner = false

    private var worktree: Worktree? {
        guard let id = pane.worktreeID else { return nil }
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
            get: { pane.showRunnerPanel },
            set: { pane.showRunnerPanel = $0 }
        )
    }

    private var showRightPanelBinding: Binding<Bool> {
        Binding(
            get: { pane.showRightPanel },
            set: { pane.showRightPanel = $0 }
        )
    }

    private var changedFileCountBinding: Binding<Int> {
        Binding(
            get: { pane.changedFileCount },
            set: { pane.changedFileCount = $0 }
        )
    }

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

    private var isFocused: Bool {
        paneManager.focusedPaneID == pane.id
    }

    /// Terminal should not grab focus while the label prompt popover is showing.
    private var terminalShouldFocus: Bool {
        isFocused && paneManager.pendingLabelPaneID != pane.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Configuration pending banner (hidden in shared layout — shown in SharedWorktreeHeaderView)
            if !isSharedLayout, let worktree, showConfigPendingBanner, worktree.project?.needsClaudeConfig == true, !isClaudeConfigRunning {
                configPendingBanner(worktree: worktree)
                Divider()
            }

            // Setup banner (hidden in shared layout — shown in SharedWorktreeHeaderView)
            if !isSharedLayout, let worktree, showSetupBanner,
               let commands = worktree.project?.profile?.setupCommands,
               !commands.filter({ !$0.isEmpty }).isEmpty {
                setupBanner(worktree: worktree, commands: commands)
                Divider()
            }

            // Unified pane header (breadcrumb hidden in shared layout — shown in SharedWorktreeHeaderView)
            PaneHeaderView(
                pane: pane,
                paneManager: paneManager,
                terminalSessionManager: terminalSessionManager,
                worktree: worktree,
                isFocused: isFocused,
                showBreadcrumb: !isSharedLayout && paneManager.expandedPanes.count > 1
            )
            Divider()

            // Terminal content
            if let worktree {
                WorktreeDetailView(
                    worktree: worktree,
                    paneId: pane.id.uuidString,
                    terminalSessionManager: terminalSessionManager,
                    paneManager: paneManager,
                    showRightPanel: showRightPanelBinding,
                    changedFileCount: changedFileCountBinding,
                    isPaneFocused: terminalShouldFocus
                )
            } else {
                emptyPanePlaceholder
            }

            // Runner panel (hidden in shared layout — shown in ContentView)
            if !isSharedLayout, let worktree {
                Divider()
                RunnerPanelView(
                    worktree: worktree,
                    terminalSessionManager: terminalSessionManager,
                    paneManager: paneManager,
                    showRunnerPanel: showRunnerPanelBinding,
                    isPaneFocused: terminalShouldFocus
                )
                .frame(maxWidth: .infinity)
                .frame(
                    minHeight: pane.showRunnerPanel ? 150 : nil,
                    idealHeight: pane.showRunnerPanel ? 250 : nil,
                    maxHeight: pane.showRunnerPanel ? 350 : nil
                )
            }
        }
        // Focus indicator: 2px accent border on all sides for focused pane, dim overlay for unfocused
        .overlay {
            if paneManager.panes.count > 1 {
                if isFocused {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                } else {
                    Color.black.opacity(0.15)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(currentTheme.background.toColor())
        .environment(\.colorScheme, currentTheme.isDark ? .dark : .light)
        .overlay(
            DropIndicatorView(zone: pane.dropZone)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            paneManager.focusedPaneID = pane.id
        }
        .task(id: pane.worktreeID) {
            if let wt = worktree {
                showConfigPendingBanner = wt.project?.needsClaudeConfig == true
                showSetupBanner = wt.needsSetup == true
                // Auto-launch Claude config when the pane first loads for a project that needs it
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
                // Auto-launch Claude config if not already running
                if let wt = worktree, !isClaudeConfigRunning,
                   claudeIntegrationService.canUseClaudeConfig {
                    openClaudeConfigTerminal(worktree: wt)
                } else {
                    showConfigPendingBanner = true
                }
            } else if newValue == false {
                showConfigPendingBanner = false
            }
        }
    }

    // MARK: - Empty Pane Placeholder

    @ViewBuilder
    private var emptyPanePlaceholder: some View {
        ContentUnavailableView(
            "No Worktree",
            systemImage: "rectangle.split.2x1",
            description: Text("Select a worktree from the sidebar to display it in this pane.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(currentTheme.background.toColor())
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
                pane.showRunnerPanel = true
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
        guard let repoPath = worktree.project?.repoPath else { return }
        ClaudeConfigHelper.openConfigTerminal(
            terminalSessionManager: terminalSessionManager,
            paneId: pane.id.uuidString,
            worktreeId: worktree.path,
            workingDirectory: worktree.path,
            repoPath: repoPath
        )
    }
}
