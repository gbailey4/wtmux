import AppKit
import SwiftUI
import SwiftData
import WTCore
import WTGit
import WTTerminal
import WTTransport

@MainActor @Observable
final class ProjectImportObserver {
    var pendingImportPath: String?
    var pendingImportConfig: ProjectConfig?

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.grahampark.wtmux.importProject"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let path = notification.object as? String
            let config: ProjectConfig? = {
                guard let json = (notification.userInfo as? [String: Any])?["config"] as? String,
                      let data = json.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(ProjectConfig.self, from: data)
            }()
            MainActor.assumeIsolated {
                self?.pendingImportConfig = config
                self?.pendingImportPath = path
            }
        }
    }
}

struct ContentView: View {
    let appDelegate: AppDelegate

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var showingAddProject = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var terminalSessionManager = TerminalSessionManager()
    @Environment(ClaudeStatusManager.self) private var claudeStatusManager
    @State private var importObserver = ProjectImportObserver()
    @State private var paneManager = SplitPaneManager()
    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @State private var gitAvailable: Bool? = nil
    @State private var gitCheckDismissed = false
    @AppStorage("claudeIntegrationDismissed") private var claudeIntegrationDismissed = false
    @State private var showCloseTabAlert = false
    @State private var pendingCloseSessionId: String?
    @State private var pendingPostCloseAction: (() -> Void)?
    @State private var showCloseWindowAlert = false
    @State private var pendingCloseWindowID: UUID?
    @State private var renamingWindowID: UUID?
    @State private var windowRenameText: String = ""
    @FocusState private var isWindowRenameFocused: Bool

    private var selectedWorktreeID: Binding<String?> {
        Binding(
            get: { paneManager.focusedColumn?.worktreeID },
            set: { newValue in
                guard let worktreeID = newValue else { return }
                // Programmatic usage (AddProjectView) — always open in new window
                paneManager.openWorktreeInNewWindow(worktreeID: worktreeID)
            }
        )
    }

    private var showRightPanel: Binding<Bool> {
        Binding(
            get: { paneManager.focusedPane?.showRightPanel ?? false },
            set: { paneManager.focusedPane?.showRightPanel = $0 }
        )
    }

    private var showRunnerPanel: Binding<Bool> {
        Binding(
            get: { paneManager.focusedColumn?.showRunnerPanel ?? false },
            set: { paneManager.focusedColumn?.showRunnerPanel = $0 }
        )
    }

    private var changedFileCount: Binding<Int> {
        Binding(
            get: { paneManager.focusedPane?.changedFileCount ?? 0 },
            set: { paneManager.focusedPane?.changedFileCount = $0 }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                projects: projects,
                paneManager: paneManager,
                showingAddProject: $showingAddProject,
                terminalSessionManager: terminalSessionManager,
                claudeStatusManager: claudeStatusManager
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detailContent
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showRightPanel.wrappedValue.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .overlay(alignment: .topTrailing) {
                            if changedFileCount.wrappedValue > 0 {
                                Text("\(changedFileCount.wrappedValue)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor, in: Capsule())
                                    .offset(x: 8, y: -8)
                            }
                        }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("Toggle Diff Panel (Cmd+Shift+D)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    paneManager.splitRight()
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
                .help("Split Right (Cmd+Shift+\\)")
                .disabled(paneManager.panes.count >= 5)
            }
        }
        .background {
            // Hidden buttons for keyboard shortcuts
            Button("Close") { handleCmdW() }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
            Button("Close Worktree") { handleCmdShiftW() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .hidden()
            Button("Focus Next Pane") { paneManager.focusNextPane() }
                .keyboardShortcut("]", modifiers: .command)
                .hidden()
            Button("Focus Previous Pane") { paneManager.focusPreviousPane() }
                .keyboardShortcut("[", modifiers: .command)
                .hidden()
        }
        .task {
            appDelegate.terminalSessionManager = terminalSessionManager
            paneManager.terminalSessionManager = terminalSessionManager
            await checkGitAvailability()
            backfillProjectColors()
            backfillSortOrders()
        }
        .sheet(isPresented: $showingAddProject) {
            AddProjectView(
                selectedWorktreeID: selectedWorktreeID
            )
        }
        .onOpenURL { url in
            handleImportURL(url)
        }
        .onChange(of: importObserver.pendingImportPath) { _, newPath in
            guard let repoPath = newPath, !repoPath.isEmpty else { return }
            let config = importObserver.pendingImportConfig
            importObserver.pendingImportPath = nil
            importObserver.pendingImportConfig = nil
            importProject(repoPath: repoPath, config: config)
        }
        .task { registerWorktreePaths() }
        .task { await pollForConfigFiles() }
        .onChange(of: projects) { registerWorktreePaths() }
        .onChange(of: totalWorktreeCount) { registerWorktreePaths() }
        .alert("Close Window?", isPresented: $showCloseWindowAlert) {
            Button("Close", role: .destructive) {
                if let id = pendingCloseWindowID {
                    paneManager.removeWindow(id: id)
                    pendingCloseWindowID = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCloseWindowID = nil
            }
        } message: {
            Text("This window has running terminal processes. Closing it will terminate them.")
        }
        .alert("Close Terminal?", isPresented: $showCloseTabAlert) {
            Button("Close", role: .destructive) {
                if let id = pendingCloseSessionId {
                    terminalSessionManager.removeTab(sessionId: id)
                    pendingCloseSessionId = nil
                }
                pendingPostCloseAction?()
                pendingPostCloseAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCloseSessionId = nil
                pendingPostCloseAction = nil
            }
        } message: {
            Text("This terminal has a running process. Closing it will terminate the process.")
        }
    }

    private var totalWorktreeCount: Int {
        projects.reduce(0) { $0 + $1.worktrees.count }
    }

    private func registerWorktreePaths() {
        let paths = Set(projects.flatMap { $0.worktrees.map(\.path) })
        claudeStatusManager.registerWorktreePaths(paths)
    }

    private func handleImportURL(_ url: URL) {
        guard url.scheme == "wtmux",
              url.host == "import-project",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let pathItem = components.queryItems?.first(where: { $0.name == "path" }),
              let repoPath = pathItem.value,
              !repoPath.isEmpty else {
            return
        }
        importProject(repoPath: repoPath)
    }

    private func importProject(repoPath: String, config: ProjectConfig? = nil) {
        Task {
            let resolvedConfig: ProjectConfig
            if let config {
                resolvedConfig = config
            } else {
                let configService = ConfigService()
                resolvedConfig = await configService.readConfig(forRepo: repoPath) ?? ProjectConfig()
            }
            let importService = ProjectImportService()
            importService.importProject(repoPath: repoPath, config: resolvedConfig, in: modelContext)
        }
    }

    private func pollForConfigFiles() async {
        let configService = ConfigService()
        let importService = ProjectImportService()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            for project in projects where project.needsClaudeConfig == true {
                if let config = await configService.readConfig(forRepo: project.repoPath) {
                    importService.importProject(repoPath: project.repoPath, config: config, in: modelContext)
                }
            }
        }
    }

    private func checkGitAvailability() async {
        let gitPath = GitService.resolveGitPath()
        let transport = LocalTransport()
        do {
            let result = try await transport.execute([gitPath, "--version"], in: "/")
            gitAvailable = result.succeeded
        } catch {
            gitAvailable = false
        }
    }

    private func backfillSortOrders() {
        // Backfill projects: if all have sortOrder 0 and there's more than one, assign sequential values
        if projects.count > 1 && projects.allSatisfy({ $0.sortOrder == 0 }) {
            let sorted = projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for (index, project) in sorted.enumerated() {
                project.sortOrder = index
            }
        }

        // Backfill worktrees within each project
        for project in projects {
            let worktrees = project.worktrees
            if worktrees.count > 1 && worktrees.allSatisfy({ $0.sortOrder == 0 }) {
                let sorted = worktrees.sorted { $0.createdAt < $1.createdAt }
                for (index, worktree) in sorted.enumerated() {
                    worktree.sortOrder = index
                }
            }
        }

        try? modelContext.save()
    }

    private func backfillProjectColors() {
        let needsColor = projects.filter { $0.colorName == nil }
        guard !needsColor.isEmpty else { return }
        for project in needsColor {
            project.colorName = Project.nextColorName(in: modelContext)
        }
        try? modelContext.save()
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            if gitAvailable == false && !gitCheckDismissed {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Git Not Found")
                            .font(.subheadline.bold())
                        Text("Install Xcode Command Line Tools to use WTMux.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("xcode-select --install", forType: .string)
                    }
                    .controlSize(.small)
                    Button("Retry") {
                        Task { await checkGitAvailability() }
                    }
                    .controlSize(.small)
                    Button {
                        gitCheckDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
                .padding(10)
                .background(.yellow.opacity(0.15))
                Divider()
            }

            if claudeIntegrationService.claudeCodeInstalled
                && !claudeIntegrationService.mcpRegistered
                && !claudeIntegrationDismissed {
                HStack(spacing: 12) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code Integration")
                            .font(.subheadline.bold())
                        Text("Enable WTMux tools in Claude Code for automatic project configuration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Enable") {
                        do {
                            try claudeIntegrationService.enableAll()
                        } catch {
                            // Silently fail; user can use Settings
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    Button {
                        claudeIntegrationDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
                .padding(10)
                .background(.blue.opacity(0.1))
                Divider()
            }

            if !paneManager.windows.isEmpty {
                windowTabBar

                if let focusedWindow = paneManager.focusedWindow {
                    switch focusedWindow.kind {
                    case .worktrees:
                        SplitPaneContainerView(
                            paneManager: paneManager,
                            terminalSessionManager: terminalSessionManager,
                            findWorktree: findWorktree
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .diff:
                        DiffTabView(
                            window: focusedWindow,
                            paneManager: paneManager,
                            findWorktree: findWorktree
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Windows Open",
                    image: "Logo",
                    description: Text("Select a worktree from the sidebar to get started.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    WorktreeDropZone { worktreeID in
                        paneManager.openWorktreeInNewWindow(worktreeID: worktreeID)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var windowTabBar: some View {
        HStack(spacing: 0) {
            ForEach(paneManager.windows) { window in
                windowTab(for: window)
            }
            Button {
                paneManager.addWindow()
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help("New Window")
            Spacer()
        }
        .background(.bar)
    }

    @ViewBuilder
    private func windowTab(for window: WindowState) -> some View {
        let isSelected = paneManager.focusedWindowID == window.id
        HStack(spacing: 4) {
            if case .diff = window.kind {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if renamingWindowID == window.id {
                TextField("Window name", text: $windowRenameText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1)
                    .frame(minWidth: 60, maxWidth: 120)
                    .focused($isWindowRenameFocused)
                    .onSubmit { commitWindowRename(windowID: window.id) }
                    .onChange(of: isWindowRenameFocused) { _, focused in
                        if !focused { commitWindowRename(windowID: window.id) }
                    }
                    .onKeyPress(.escape) {
                        cancelWindowRename()
                        return .handled
                    }
            } else {
                Text(window.name)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        startWindowRename(window: window)
                    }
                    .onTapGesture(count: 1) {
                        paneManager.focusWindow(id: window.id)
                    }
            }
            Button {
                closeWindow(id: window.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Window")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contextMenu {
            Button("Rename...") {
                startWindowRename(window: window)
            }
        }
        .onChange(of: paneManager.focusedWindowID) { _, _ in
            if renamingWindowID == window.id {
                commitWindowRename(windowID: window.id)
            }
        }
    }

    private func startWindowRename(window: WindowState) {
        windowRenameText = window.name
        renamingWindowID = window.id
        isWindowRenameFocused = true
    }

    private func cancelWindowRename() {
        renamingWindowID = nil
    }

    private func commitWindowRename(windowID: UUID) {
        guard renamingWindowID == windowID else { return }
        let trimmed = windowRenameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            paneManager.renameWindow(id: windowID, name: trimmed)
        }
        renamingWindowID = nil
    }

    // MARK: - Window Close

    private func closeWindow(id: UUID) {
        if windowHasRunningProcesses(id: id) {
            pendingCloseWindowID = id
            showCloseWindowAlert = true
        } else {
            paneManager.removeWindow(id: id)
        }
    }

    private func windowHasRunningProcesses(id: UUID) -> Bool {
        guard let window = paneManager.windows.first(where: { $0.id == id }) else { return false }
        for column in window.columns {
            for pane in column.panes {
                let tabs = terminalSessionManager.orderedSessions(forPane: pane.id.uuidString)
                if tabs.contains(where: { $0.terminalView?.hasChildProcesses() == true }) {
                    return true
                }
            }
            if let worktreeID = column.worktreeID {
                let othersHaveIt = paneManager.windows.contains { w in
                    w.id != id && w.columns.contains { $0.worktreeID == worktreeID }
                }
                if !othersHaveIt {
                    let runners = terminalSessionManager.sessions(forWorktree: worktreeID)
                        .filter { SessionID.isRunner($0.id) && $0.state == .running }
                    if !runners.isEmpty { return true }
                }
            }
        }
        return false
    }

    // MARK: - Cmd+W / Cmd+Shift+W

    private func handleCmdW() {
        // Close diff tab first if focused
        if let focusedWindow = paneManager.focusedWindow,
           case .diff = focusedWindow.kind {
            paneManager.closeDiffTab(windowID: focusedWindow.id)
            return
        }

        guard let pane = paneManager.focusedPane else {
            return
        }

        let paneId = pane.id.uuidString
        guard let column = paneManager.column(forPane: pane.id),
              column.worktreeID != nil else {
            // Empty pane/column — close the pane
            paneManager.closeFocusedPane()
            return
        }

        let tabs = terminalSessionManager.orderedSessions(forPane: paneId)
        let activeId = terminalSessionManager.activeSessionId[paneId]
        guard let activeTab = tabs.first(where: { $0.id == activeId }) ?? tabs.last else {
            // No tabs — close the pane
            paneManager.closeFocusedPane()
            return
        }

        if activeTab.terminalView?.hasChildProcesses() == true {
            pendingCloseSessionId = activeTab.id
            pendingPostCloseAction = { [weak paneManager, weak terminalSessionManager] in
                guard let paneManager, let terminalSessionManager else { return }
                cascadeAfterTabClose(paneId: paneId, paneManager: paneManager, terminalSessionManager: terminalSessionManager)
            }
            showCloseTabAlert = true
        } else {
            terminalSessionManager.removeTab(sessionId: activeTab.id)
            cascadeAfterTabClose(paneId: paneId, paneManager: paneManager, terminalSessionManager: terminalSessionManager)
        }
    }

    private func cascadeAfterTabClose(paneId: String, paneManager: SplitPaneManager, terminalSessionManager: TerminalSessionManager) {
        let remaining = terminalSessionManager.orderedSessions(forPane: paneId)
        if !remaining.isEmpty { return }
        paneManager.closeFocusedPane()
    }

    private func handleCmdShiftW() {
        guard let column = paneManager.focusedColumn,
              let worktreeID = column.worktreeID else { return }

        let tabs = terminalSessionManager.sessions(forWorktree: worktreeID)
        let hasRunning = tabs.contains { $0.terminalView?.hasChildProcesses() == true }

        if hasRunning {
            pendingPostCloseAction = { [weak paneManager] in
                paneManager?.clearWorktree(worktreeID)
            }
            showCloseTabAlert = true
        } else {
            paneManager.clearWorktree(worktreeID)
        }
    }

    private func findWorktree(id: String) -> Worktree? {
        for project in projects {
            if let wt = project.worktrees.first(where: { $0.path == id }) {
                return wt
            }
        }
        return nil
    }
}

// MARK: - WorktreeDropZone

/// AppKit-level drop target for worktree drags.
/// Reads the pasteboard synchronously (matching DroppableSplitView's proven approach)
/// because SwiftUI's NSItemProvider async loading cancels for custom UTTypes.
private struct WorktreeDropZone: NSViewRepresentable {
    var onDrop: (String) -> Void

    func makeNSView(context: Context) -> DropTargetView {
        let view = DropTargetView()
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DropTargetView, context: Context) {
        nsView.onDrop = onDrop
    }

    final class DropTargetView: NSView {
        var onDrop: ((String) -> Void)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([WorktreeReference.pasteboardType])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        // Pass clicks through to the SwiftUI view underneath
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let pasteboard = sender.draggingPasteboard
            var data = pasteboard.data(forType: WorktreeReference.pasteboardType)
            if data == nil, let item = pasteboard.pasteboardItems?.first {
                data = item.data(forType: WorktreeReference.pasteboardType)
            }
            guard let data,
                  let ref = try? JSONDecoder().decode(WorktreeReference.self, from: data)
            else { return false }
            onDrop?(ref.worktreeID)
            return true
        }
    }
}
