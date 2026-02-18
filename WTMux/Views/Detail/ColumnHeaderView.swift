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

    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @Environment(ThemeManager.self) private var themeManager
    @Environment(ClaudeStatusManager.self) private var claudeStatusManager

    @State private var showCloseColumnAlert = false
    @State private var isOverflowHovered = false
    @State private var isCloseHovered = false

    @State private var renamingTabId: String?
    @State private var renameText: String = ""
    @State private var renameError: Bool = false
    @FocusState private var isRenameFieldFocused: Bool

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

    private var columnId: String { column.id.uuidString }

    private var terminalTabs: [TerminalSession] {
        terminalSessionManager.orderedSessions(forColumn: columnId)
    }

    private var claudeStatus: ClaudeCodeStatus? {
        guard let worktreeId = column.worktreeID else { return nil }
        return claudeStatusManager.status(forColumn: columnId, worktreePath: worktreeId)
    }

    private var activeTabId: String? {
        terminalSessionManager.activeSessionId[columnId]
    }

    private var hasRunningProcesses: Bool {
        terminalTabs.contains { $0.terminalView?.hasChildProcesses() == true }
    }

    private var showFocusBorder: Bool {
        paneManager.columns.count > 1
    }

    var body: some View {
        HStack(spacing: 0) {
            // Project / branch info
            projectBranchLabel
                .padding(.leading, 8)

            // Terminal tabs
            if !terminalTabs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(terminalTabs) { session in
                            terminalTab(session: session)
                        }
                    }
                }
                .padding(.leading, 6)
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
            Button("New Terminal Tab") {
                createNewTerminalTab()
            }
            Button("New Column (Same Worktree)") {
                paneManager.addColumn(worktreeID: column.worktreeID, after: column.id)
            }
            .disabled(paneManager.columns.count >= 5)

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
            // New tab button
            Button {
                createNewTerminalTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Terminal Tab")

            // Overflow menu
            Menu {
                Button("New Terminal Tab") {
                    createNewTerminalTab()
                }
                Button("New Column (Same Worktree)") {
                    paneManager.addColumn(worktreeID: column.worktreeID, after: column.id)
                }
                .disabled(paneManager.columns.count >= 5)

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
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .background(isOverflowHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { isOverflowHovered = $0 }
            .help("Column Options")

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

    // MARK: - Terminal Tabs

    @ViewBuilder
    private func terminalTab(session: TerminalSession) -> some View {
        HStack(spacing: 4) {
            if renamingTabId == session.id {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Tab name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(minWidth: 50, maxWidth: 100)
                        .focused($isRenameFieldFocused)
                        .onSubmit { commitRename(sessionId: session.id) }
                        .onChange(of: isRenameFieldFocused) { _, focused in
                            if !focused { commitRename(sessionId: session.id) }
                        }
                        .onChange(of: renameText) { _, _ in renameError = false }
                        .onKeyPress(.escape) {
                            cancelRename()
                            return .handled
                        }
                    if renameError {
                        Text("Name already in use")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Text(session.title)
                    .font(.caption)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        startRename(session: session)
                    }
                    .onTapGesture(count: 1) {
                        terminalSessionManager.setActiveSession(columnId: columnId, sessionId: session.id)
                        paneManager.focusedColumnID = column.id
                    }
            }

            Button {
                closeTab(session: session)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(session.id == activeTabId ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .draggable(TerminalTabReference(columnId: columnId, sessionId: session.id))
        .dropDestination(for: TerminalTabReference.self) { droppedRefs, _ in
            guard let ref = droppedRefs.first else { return false }
            let targetIndex = terminalTabs.firstIndex(where: { $0.id == session.id }) ?? terminalTabs.count
            if ref.columnId == columnId {
                // Intra-column reorder
                guard ref.sessionId != session.id else { return false }
                terminalSessionManager.moveTab(sessionId: ref.sessionId, toIndex: targetIndex, inColumn: columnId)
            } else {
                // Cross-column move: move tab to this column
                guard let fromColumnUUID = UUID(uuidString: ref.columnId) else { return false }
                paneManager.moveTabToColumn(sessionId: ref.sessionId, fromColumnId: fromColumnUUID, toColumnId: column.id)
            }
            return true
        }
    }

    // MARK: - Tab Actions

    private func createNewTerminalTab() {
        let startCommand: String? = {
            guard let cmd = worktree?.project?.profile?.terminalStartCommand, !cmd.isEmpty else { return nil }
            return cmd
        }()
        _ = terminalSessionManager.createTab(
            forColumn: columnId,
            worktreeId: worktree?.path ?? "",
            workingDirectory: worktree?.path ?? "",
            initialCommand: startCommand
        )
    }

    private func closeTab(session: TerminalSession) {
        if session.terminalView?.hasChildProcesses() == true {
            // For now, close directly — ContentView's Cmd+W handles confirmation
            terminalSessionManager.removeTab(sessionId: session.id)
            cascadeIfEmpty()
        } else {
            terminalSessionManager.removeTab(sessionId: session.id)
            cascadeIfEmpty()
        }
    }

    private func cascadeIfEmpty() {
        if terminalSessionManager.orderedSessions(forColumn: columnId).isEmpty {
            paneManager.removeColumn(id: column.id)
        }
    }

    private func startRename(session: TerminalSession) {
        renameText = session.title
        renamingTabId = session.id
        isRenameFieldFocused = true
    }

    private func commitRename(sessionId: String) {
        guard renamingTabId == sessionId else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            if !terminalSessionManager.renameTab(sessionId: sessionId, to: trimmed) {
                renameError = true
                return
            }
        }
        renameError = false
        renamingTabId = nil
    }

    private func cancelRename() {
        renamingTabId = nil
    }
}
