import os.log
import SwiftUI
import WTCore
import WTTerminal

private let dragLogger = Logger(subsystem: "com.wtmux", category: "PaneHeaderDrag")

struct PaneHeaderView: View {
    let pane: WorktreePane
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let worktree: Worktree?
    var isFocused: Bool = false
    var showBreadcrumb: Bool = true

    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @AppStorage("promptForPaneLabel") private var promptForPaneLabel = true
    @Environment(ThemeManager.self) private var themeManager
    @Environment(ClaudeStatusManager.self) private var claudeStatusManager

    @State private var showClosePaneAlert = false
    @State private var isCloseHovered = false
    @State private var isEditingLabel = false
    @State private var editingLabelText = ""
    @State private var isLabelHovered = false
    @State private var promptDontAsk = false
    @FocusState private var isLabelFieldFocused: Bool
    @FocusState private var isPromptFieldFocused: Bool

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

    private var paneId: String { pane.id.uuidString }

    private var claudeStatus: ClaudeCodeStatus? {
        guard let worktreeId = pane.worktreeID else { return nil }
        return claudeStatusManager.status(forPane: paneId, worktreePath: worktreeId)
    }

    private var hasRunningProcesses: Bool {
        terminalSessionManager.terminalSession(forPane: paneId)?.terminalView?.hasChildProcesses() == true
    }

    private var showFocusBorder: Bool {
        paneManager.expandedPanes.count > 1
    }

    var body: some View {
        HStack(spacing: 0) {
            // Project / branch info
            if showBreadcrumb {
                projectBranchLabel
                    .padding(.leading, 8)
            }
            if let claudeStatus {
                claudeStatusBadge(claudeStatus)
                    .padding(.leading, showBreadcrumb ? 0 : 8)
            }

            paneLabelView
                .padding(.leading, 6)
                .popover(isPresented: showLabelPromptBinding, arrowEdge: .bottom) {
                    labelPromptPopover
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
            paneManager.focusedPaneID = pane.id
        }
        .alert("Close Pane?", isPresented: $showClosePaneAlert) {
            Button("Close", role: .destructive) {
                paneManager.removePane(id: pane.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This pane has running terminal processes. Closing it will terminate them.")
        }
        .contextMenu {
            Button("Minimize") {
                paneManager.minimizePane(id: pane.id)
            }
            .disabled(pane.worktreeID == nil)

            Divider()

            Button("Move to New Window") {
                paneManager.movePaneToNewWindow(paneID: pane.id)
            }
            .disabled(paneManager.focusedWindow?.panes.count ?? 0 <= 1)

            if paneManager.windows.count > 1 {
                Menu("Move to Window\u{2026}") {
                    ForEach(paneManager.windows.filter({ $0.id != paneManager.focusedWindowID })) { window in
                        Button(window.name) {
                            paneManager.movePaneToWindow(paneID: pane.id, targetWindowID: window.id)
                        }
                    }
                }
            }

            Divider()

            Button("New Pane (Same Worktree)") {
                paneManager.addPane(worktreeID: pane.worktreeID, after: pane.id)
            }
            .disabled(paneManager.panes.count >= 5)

            Divider()

            Button("Set Label\u{2026}") {
                beginLabelEdit()
            }

            if let label = pane.label, !label.isEmpty {
                Button(pane.showLabel ? "Hide Label" : "Show Label") {
                    pane.showLabel.toggle()
                    paneManager.saveStateExternally()
                }

                Button("Clear Label") {
                    pane.label = nil
                    paneManager.saveStateExternally()
                }
            }
        }
        .draggable(WorktreeReference(
            worktreeID: pane.worktreeID ?? "",
            sourcePaneID: pane.id.uuidString
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
            }
        } else {
            Text("Empty Pane")
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

    // MARK: - Pane Label

    @ViewBuilder
    private var paneLabelView: some View {
        if isEditingLabel {
            TextField("Label", text: $editingLabelText)
                .font(.caption)
                .textFieldStyle(.plain)
                .frame(maxWidth: 160)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                .focused($isLabelFieldFocused)
                .onSubmit { commitLabel() }
                .onExitCommand { cancelLabelEdit() }
                .onChange(of: editingLabelText) {
                    if editingLabelText.count > 50 {
                        editingLabelText = String(editingLabelText.prefix(50))
                    }
                }
                .onAppear { isLabelFieldFocused = true }
        } else if let label = pane.label, !label.isEmpty, pane.showLabel {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(label)
                .onTapGesture { beginLabelEdit() }
        } else {
            Image(systemName: "pencil")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .onTapGesture { beginLabelEdit() }
                .opacity(isLabelHovered ? 1 : 0)
                .onHover { isLabelHovered = $0 }
        }
    }

    private func beginLabelEdit() {
        editingLabelText = pane.label ?? ""
        isEditingLabel = true
    }

    private func commitLabel() {
        let trimmed = editingLabelText.trimmingCharacters(in: .whitespaces)
        pane.label = trimmed.isEmpty ? nil : trimmed
        isEditingLabel = false
        paneManager.saveStateExternally()
    }

    private func cancelLabelEdit() {
        isEditingLabel = false
    }

    // MARK: - Label Prompt

    private var showLabelPromptBinding: Binding<Bool> {
        Binding(
            get: { paneManager.pendingLabelPaneID == pane.id },
            set: { if !$0 { paneManager.pendingLabelPaneID = nil } }
        )
    }

    @ViewBuilder
    private var labelPromptPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Label this pane")
                .font(.headline)

            TextField("What are you working on?", text: $editingLabelText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused($isPromptFieldFocused)
                .onSubmit { commitLabelPrompt() }
                .onChange(of: editingLabelText) {
                    if editingLabelText.count > 50 {
                        editingLabelText = String(editingLabelText.prefix(50))
                    }
                }

            Toggle("Don\u{2019}t ask for new panes", isOn: $promptDontAsk)
                .font(.caption)

            HStack {
                Spacer()
                Button("Skip") {
                    dismissLabelPrompt()
                }
                .keyboardShortcut(.cancelAction)
                Button("Done") {
                    commitLabelPrompt()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editingLabelText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .onAppear {
            editingLabelText = ""
            promptDontAsk = false
            // Delay focus until the popover window is fully established,
            // otherwise the terminal view steals first responder.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPromptFieldFocused = true
            }
        }
    }

    private func commitLabelPrompt() {
        let trimmed = editingLabelText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            pane.label = trimmed
            pane.showLabel = true
            paneManager.saveStateExternally()
        }
        if promptDontAsk {
            promptForPaneLabel = false
        }
        paneManager.pendingLabelPaneID = nil
    }

    private func dismissLabelPrompt() {
        if promptDontAsk {
            promptForPaneLabel = false
        }
        paneManager.pendingLabelPaneID = nil
    }

    // MARK: - Header Buttons

    @ViewBuilder
    private var headerButtons: some View {
        HStack(spacing: 2) {
            // Minimize button
            if pane.worktreeID != nil {
                Button {
                    paneManager.minimizePane(id: pane.id)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Minimize Pane")
            }

            // New pane button
            Button {
                paneManager.addPane(worktreeID: pane.worktreeID, after: pane.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Pane")
            .disabled(paneManager.panes.count >= 5)

            // Close button
            Button {
                if hasRunningProcesses {
                    showClosePaneAlert = true
                } else {
                    paneManager.removePane(id: pane.id)
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
            .help("Close Pane")
        }
    }
}
