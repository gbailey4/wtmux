import SwiftUI
import WTCore
import WTDiff
import WTGit
import WTTerminal
import WTTransport
import WTSSH

struct WorktreeDetailView: View {
    let worktree: Worktree
    let paneId: String
    let terminalSessionManager: TerminalSessionManager
    let paneManager: SplitPaneManager
    @Binding var showRightPanel: Bool
    @Binding var changedFileCount: Int
    var isPaneFocused: Bool = true

    @Environment(\.sshConnectionManager) private var sshConnectionManager
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id

    @State private var showCloseTabAlert = false
    @State private var pendingCloseSessionId: String?
    @State private var renamingTabId: String?
    @State private var renameText: String = ""
    @State private var renameError: Bool = false
    @FocusState private var isRenameFieldFocused: Bool

    private var currentTheme: TerminalTheme {
        TerminalThemes.theme(forId: terminalThemeId)
    }

    private var worktreeId: String { worktree.path }

    private var terminalTabs: [TerminalSession] {
        terminalSessionManager.orderedSessions(forPane: paneId)
    }

    private var activeTabId: String? {
        terminalSessionManager.activeSessionId[paneId]
    }

    private var paneUUID: UUID {
        UUID(uuidString: paneId) ?? UUID()
    }

    private var isDiffActive: Bool {
        paneManager.activeDiffPaneID == paneUUID && paneManager.activeDiffFile != nil
    }

    var body: some View {
        Group {
            if isDiffActive, let diffFile = paneManager.activeDiffFile {
                diffContent(file: diffFile)
            } else {
                normalContent
            }
        }
        .task(id: "\(worktreeId)-\(paneId)") {
            // Close diff if it belonged to this pane
            if paneManager.activeDiffPaneID == UUID(uuidString: paneId) {
                paneManager.closeDiff()
            }
            changedFileCount = 0
            ensureFirstTab()
            let transport: CommandTransport = worktree.project.map { $0.makeTransport(connectionManager: sshConnectionManager) } ?? LocalTransport()
            let git = GitService(transport: transport, repoPath: worktree.path)
            if let files = try? await git.status() {
                changedFileCount = files.count
            }
        }
        .alert("Close Terminal?", isPresented: $showCloseTabAlert) {
            Button("Close", role: .destructive) {
                if let id = pendingCloseSessionId {
                    terminalSessionManager.removeTab(sessionId: id)
                    pendingCloseSessionId = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCloseSessionId = nil
            }
        } message: {
            Text("This terminal has a running process. Closing it will terminate the process.")
        }
    }

    private func ensureFirstTab() {
        guard terminalSessionManager.orderedSessions(forPane: paneId).isEmpty else { return }

        let startCommand: String? = {
            guard let cmd = worktree.project?.profile?.terminalStartCommand, !cmd.isEmpty else { return nil }
            return cmd
        }()

        let session = terminalSessionManager.createTab(
            forPane: paneId,
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            initialCommand: startCommand
        )
        configureSSHIfNeeded(session)
    }

    // MARK: - Tabbed Terminal

    private func createNewTerminalTab() {
        let startCommand: String? = {
            guard let cmd = worktree.project?.profile?.terminalStartCommand, !cmd.isEmpty else { return nil }
            return cmd
        }()
        let session = terminalSessionManager.createTab(
            forPane: paneId,
            worktreeId: worktreeId,
            workingDirectory: worktree.path,
            initialCommand: startCommand
        )
        configureSSHIfNeeded(session)
    }

    private func configureSSHIfNeeded(_ session: TerminalSession) {
        guard let project = worktree.project, project.isRemote,
              let config = project.sshConfig() else { return }
        session.isSSH = true
        session.sshConnectionManager = sshConnectionManager
        session.sshConnectionConfig = config
    }

    @ViewBuilder
    private var tabbedTerminalView: some View {
        VStack(spacing: 0) {
            if !terminalTabs.isEmpty {
                terminalTabBar
            }
            ZStack {
                ForEach(terminalTabs) { session in
                    let isActiveTab = session.id == activeTabId
                    if session.isSSH {
                        SSHTerminalRepresentable(session: session, isActive: isActiveTab && isPaneFocused, theme: currentTheme)
                            .opacity(isActiveTab ? 1 : 0)
                            .allowsHitTesting(isActiveTab)
                    } else {
                        TerminalRepresentable(session: session, isActive: isActiveTab && isPaneFocused, theme: currentTheme)
                            .opacity(isActiveTab ? 1 : 0)
                            .allowsHitTesting(isActiveTab)
                    }
                }
                if terminalTabs.isEmpty {
                    ContentUnavailableView {
                        Label("No Terminal", systemImage: "terminal")
                    } description: {
                        Text("Open a new terminal to get started.")
                    } actions: {
                        Button("New Terminal") {
                            createNewTerminalTab()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var terminalTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(terminalTabs) { session in
                        terminalTab(session: session)
                    }
                }
            }

            Spacer()

            // Split button: [+] creates tab, [chevron] opens menu
            HStack(spacing: 0) {
                Button {
                    createNewTerminalTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 12)

                Menu {
                    Button("New Terminal Tab") {
                        createNewTerminalTab()
                    }
                    Button("New Terminal in Split") {
                        paneManager.splitSameWorktree()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.trailing, 4)
        }
        .contextMenu {
            Button("New Terminal Tab") {
                createNewTerminalTab()
            }
            Button("New Terminal in Split") {
                paneManager.splitSameWorktree()
            }
        }
        .background(.bar)
    }

    @ViewBuilder
    private func terminalTab(session: TerminalSession) -> some View {
        HStack(spacing: 4) {
            if renamingTabId == session.id {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Tab name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1)
                        .frame(minWidth: 60, maxWidth: 120)
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
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Text(session.title)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        startRename(session: session)
                    }
                    .onTapGesture(count: 1) {
                        terminalSessionManager.setActiveSession(paneId: paneId, sessionId: session.id)
                    }
            }

            Button {
                let hasRunningProcess = session.isSSH
                    ? (session.sshTerminalView?.isSessionActive == true)
                    : (session.terminalView?.hasChildProcesses() == true)
                if hasRunningProcess {
                    pendingCloseSessionId = session.id
                    showCloseTabAlert = true
                } else {
                    terminalSessionManager.removeTab(sessionId: session.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(session.id == activeTabId ? Color.accentColor.opacity(0.2) : Color.clear)
        .draggable(session.id)
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let droppedId = droppedIds.first,
                  droppedId != session.id,
                  let targetIndex = terminalTabs.firstIndex(where: { $0.id == session.id }) else { return false }
            terminalSessionManager.moveTab(sessionId: droppedId, toIndex: targetIndex, inPane: paneId)
            return true
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

    // MARK: - Normal vs Diff Content

    @ViewBuilder
    private var normalContent: some View {
        HStack(spacing: 0) {
            tabbedTerminalView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showRightPanel {
                Divider()
                ChangesPanel(
                    worktree: worktree,
                    paneManager: paneManager,
                    paneID: paneUUID,
                    changedFileCount: $changedFileCount
                )
                .frame(width: 400)
            }
        }
    }

    @ViewBuilder
    private func diffContent(file: DiffFile) -> some View {
        HStack(spacing: 0) {
            DiffContentView(
                file: file,
                onClose: { paneManager.closeDiff() },
                backgroundColor: currentTheme.background.toColor(),
                foregroundColor: currentTheme.foreground.toColor()
            ) {
                openInEditorMenu(relativePath: file.displayPath)
            }
            .environment(\.colorScheme, currentTheme.isDark ? .dark : .light)

            Divider()

            ChangesPanel(
                worktree: worktree,
                paneManager: paneManager,
                paneID: paneUUID,
                changedFileCount: $changedFileCount
            )
            .frame(width: 400)
        }
        .onKeyPress(.escape) {
            paneManager.closeDiff()
            return .handled
        }
    }

    @ViewBuilder
    private func openInEditorMenu(relativePath: String) -> some View {
        let editors = ExternalEditor.installedEditors(custom: ExternalEditor.customEditors)
        Menu {
            ForEach(editors) { editor in
                Button(editor.name) {
                    let fileURL = URL(fileURLWithPath: worktree.path)
                        .appendingPathComponent(relativePath)
                    ExternalEditor.open(fileURL: fileURL, editor: editor)
                }
            }
            Divider()
            SettingsLink {
                Text("Configure Editors...")
            }
        } label: {
            Image(systemName: "arrow.up.forward.square")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
