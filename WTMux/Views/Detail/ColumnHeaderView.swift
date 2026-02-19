import os.log
import SwiftUI
import WTCore
import WTTerminal

private let dragLogger = Logger(subsystem: "com.wtmux", category: "ColumnHeaderDrag")

struct ColumnHeaderView: View {
    let column: WorktreeColumn
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let worktree: Worktree?
    var isFocused: Bool = false
    var showBreadcrumb: Bool = true

    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @Environment(ThemeManager.self) private var themeManager
    @Environment(ClaudeStatusManager.self) private var claudeStatusManager

    @State private var showCloseColumnAlert = false
    @State private var isCloseHovered = false

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

    private var columnId: String { column.id.uuidString }

    private var claudeStatus: ClaudeCodeStatus? {
        guard let worktreeId = column.worktreeID else { return nil }
        return claudeStatusManager.status(forColumn: columnId, worktreePath: worktreeId)
    }

    private var hasRunningProcesses: Bool {
        terminalSessionManager.terminalSession(forColumn: columnId)?.terminalView?.hasChildProcesses() == true
    }

    private var showFocusBorder: Bool {
        paneManager.expandedColumns.count > 1
    }

    var body: some View {
        HStack(spacing: 0) {
            // Project / branch info
            if showBreadcrumb {
                projectBranchLabel
                    .padding(.leading, 8)
            }

            Spacer()

            // Action buttons
            headerButtons
                .padding(.trailing, 4)
        }
        .padding(.vertical, 5)
        .background {
            if isFocused {
                ZStack {
                    currentTheme.chromeBackground.toColor()
                    Color.accentColor.opacity(0.18)
                }
            } else {
                currentTheme.chromeBackground.toColor()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            paneManager.focusedColumnID = column.id
        }
        .alert("Close Column?", isPresented: $showCloseColumnAlert) {
            Button("Close", role: .destructive) {
                paneManager.removeColumn(id: column.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This column has running terminal processes. Closing it will terminate them.")
        }
        .contextMenu {
            Button("Minimize") {
                paneManager.minimizeColumn(id: column.id)
            }
            .disabled(column.worktreeID == nil)

            Divider()

            Button("Move to New Window") {
                paneManager.moveColumnToNewWindow(columnID: column.id)
            }
            .disabled(paneManager.focusedWindow?.columns.count ?? 0 <= 1)

            if paneManager.windows.count > 1 {
                Menu("Move to Window\u{2026}") {
                    ForEach(paneManager.windows.filter({ $0.id != paneManager.focusedWindowID })) { window in
                        Button(window.name) {
                            paneManager.moveColumnToWindow(columnID: column.id, targetWindowID: window.id)
                        }
                    }
                }
            }

            Divider()

            Button("New Column (Same Worktree)") {
                paneManager.addColumn(worktreeID: column.worktreeID, after: column.id)
            }
            .disabled(paneManager.columns.count >= 5)
        }
        .draggable(WorktreeReference(
            worktreeID: column.worktreeID ?? "",
            sourcePaneID: column.id.uuidString
        )) {
            HStack(spacing: 4) {
                if let worktree {
                    Text(worktree.branchName)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Project / Branch Label

    @ViewBuilder
    private var projectBranchLabel: some View {
        if let worktree {
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
                if let claudeStatus {
                    claudeStatusBadge(claudeStatus)
                }
            }
        } else {
            Text("Empty Column")
                .font(.caption)
                .foregroundStyle(.tertiary)
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

    // MARK: - Header Buttons

    @ViewBuilder
    private var headerButtons: some View {
        HStack(spacing: 2) {
            // Minimize button
            if column.worktreeID != nil {
                Button {
                    paneManager.minimizeColumn(id: column.id)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Minimize Column")
            }

            // New column button
            Button {
                paneManager.addColumn(worktreeID: column.worktreeID, after: column.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Column")
            .disabled(paneManager.columns.count >= 5)

            // Close button
            Button {
                if hasRunningProcesses {
                    showCloseColumnAlert = true
                } else {
                    paneManager.removeColumn(id: column.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .background(isCloseHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .help("Close Column")
        }
    }
}
