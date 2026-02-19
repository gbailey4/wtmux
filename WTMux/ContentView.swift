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
            forName: AppIdentity.importProjectNotification,
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
    @State private var terminalSessionManager = TerminalSessionManager()
    @Environment(ClaudeStatusManager.self) private var claudeStatusManager
    @State private var importObserver = ProjectImportObserver()
    @State private var paneManager = SplitPaneManager()
    @Environment(ClaudeIntegrationService.self) private var claudeIntegrationService
    @State private var gitAvailable: Bool? = nil
    @State private var gitCheckDismissed = false
    @AppStorage("claudeIntegrationDismissed") private var claudeIntegrationDismissed = false
    @State private var showCloseColumnAlert = false
    @State private var pendingCloseColumnID: UUID?
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id
    @Environment(ThemeManager.self) private var themeManager
    @State private var sidebarCollapsed = false
    @State private var showCloseWindowAlert = false
    @State private var pendingCloseWindowID: UUID?
    @State private var renamingWindowID: UUID?
    @State private var windowRenameText: String = ""
    @FocusState private var isWindowRenameFocused: Bool

    private var currentTheme: TerminalTheme {
        themeManager.theme(forId: terminalThemeId)
    }

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
            get: { paneManager.focusedColumn?.showRightPanel ?? false },
            set: { paneManager.focusedColumn?.showRightPanel = $0 }
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
            get: { paneManager.focusedColumn?.changedFileCount ?? 0 },
            set: { paneManager.focusedColumn?.changedFileCount = $0 }
        )
    }

    var body: some View {
        HSplitView {
            SidebarView(
                projects: projects,
                paneManager: paneManager,
                showingAddProject: $showingAddProject,
                terminalSessionManager: terminalSessionManager,
                claudeStatusManager: claudeStatusManager
            )
            .frame(minWidth: sidebarCollapsed ? 0 : 200, idealWidth: 240, maxWidth: 320)
            .background { SidebarCollapser(isCollapsed: sidebarCollapsed) }

            detailContent
                .padding(.leading, 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sidebarCollapsed.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
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
                .disabled(paneManager.columns.count >= 5)
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
            Button("Focus Next Column") { paneManager.focusNextColumn() }
                .keyboardShortcut("]", modifiers: .command)
                .hidden()
            Button("Focus Previous Column") { paneManager.focusPreviousColumn() }
                .keyboardShortcut("[", modifiers: .command)
                .hidden()
            Button("Move to New Window") {
                if let columnID = paneManager.focusedColumnID {
                    paneManager.moveColumnToNewWindow(columnID: columnID)
                }
            }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .hidden()
            Button("Move to Next Window") { paneManager.moveColumnToNextWindow() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .hidden()
            Button("Move to Previous Window") { paneManager.moveColumnToPreviousWindow() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
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
        .alert("Close Column?", isPresented: $showCloseColumnAlert) {
            Button("Close", role: .destructive) {
                if let id = pendingCloseColumnID {
                    paneManager.removeColumn(id: id)
                    pendingCloseColumnID = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCloseColumnID = nil
            }
        } message: {
            Text("This column has a running terminal process. Closing it will terminate the process.")
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
                        let sharedWtID = paneManager.sharedWorktreeID
                        let sharedWorktree = sharedWtID.flatMap { findWorktree(id: $0) }

                        VStack(spacing: 0) {
                            if let worktree = sharedWorktree {
                                SharedWorktreeHeaderView(
                                    worktree: worktree,
                                    paneManager: paneManager,
                                    terminalSessionManager: terminalSessionManager
                                )
                                Divider()
                            }

                            SplitPaneContainerView(
                                paneManager: paneManager,
                                terminalSessionManager: terminalSessionManager,
                                findWorktree: findWorktree,
                                isSharedLayout: sharedWorktree != nil
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            if let worktree = sharedWorktree {
                                Divider()
                                RunnerPanelView(
                                    worktree: worktree,
                                    terminalSessionManager: terminalSessionManager,
                                    paneManager: paneManager,
                                    showRunnerPanel: showRunnerPanel,
                                    isColumnFocused: true
                                )
                                .frame(maxWidth: .infinity)
                                .frame(
                                    minHeight: showRunnerPanel.wrappedValue ? 150 : nil,
                                    idealHeight: showRunnerPanel.wrappedValue ? 250 : nil,
                                    maxHeight: showRunnerPanel.wrappedValue ? 350 : nil
                                )
                            }
                        }
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
                .background(currentTheme.background.toColor())
                .environment(\.colorScheme, currentTheme.isDark ? .dark : .light)
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
                    .overlay {
                        WindowTabDropTarget(windowID: window.id, paneManager: paneManager)
                    }
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
                .overlay {
                    WindowTabDropTarget(windowID: nil, paneManager: paneManager)
                }
        }
        .background(currentTheme.chromeBackground.toColor())
        .environment(\.colorScheme, currentTheme.isDark ? .dark : .light)
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
            if let session = terminalSessionManager.terminalSession(forColumn: column.id.uuidString),
               session.terminalView?.hasChildProcesses() == true {
                return true
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

        guard let column = paneManager.focusedColumn else { return }

        let columnId = column.id.uuidString

        // Check if terminal has running processes
        if let session = terminalSessionManager.terminalSession(forColumn: columnId),
           session.terminalView?.hasChildProcesses() == true {
            pendingCloseColumnID = column.id
            showCloseColumnAlert = true
        } else {
            paneManager.closeFocusedColumn()
        }
    }

    private func handleCmdShiftW() {
        guard let column = paneManager.focusedColumn,
              let worktreeID = column.worktreeID else { return }

        let sessions = terminalSessionManager.sessions(forWorktree: worktreeID)
        let hasRunning = sessions.contains { $0.terminalView?.hasChildProcesses() == true }

        if hasRunning {
            // Reuse the close column alert for the whole worktree
            pendingCloseColumnID = column.id
            showCloseColumnAlert = true
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

// MARK: - SidebarCollapser

/// Programmatically collapses/expands the sidebar by calling NSSplitView's
/// `setPosition(_:ofDividerAt:)`. Placed as a `.background` on the sidebar
/// so its NSView is a descendant of the NSSplitView.
/// Also observes sidebar frame changes to persist the user's preferred width.
private struct SidebarCollapser: NSViewRepresentable {
    var isCollapsed: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let splitView = findSplitView(from: nsView) else { return }
            context.coordinator.installObserver(on: splitView)
            if isCollapsed {
                splitView.setPosition(0, ofDividerAt: 0)
            } else if !context.coordinator.hasRestoredWidth
                        || splitView.subviews.first.map({ $0.frame.width < 1 }) == true {
                context.coordinator.hasRestoredWidth = true
                let saved = UserDefaults.standard.double(forKey: "sidebarWidth")
                let width = (200...320).contains(saved) ? saved : 240
                splitView.setPosition(width, ofDividerAt: 0)
            }
        }
    }

    private func findSplitView(from view: NSView) -> NSSplitView? {
        var current: NSView? = view.superview
        while let v = current {
            if let split = v as? NSSplitView { return split }
            current = v.superview
        }
        return nil
    }

    final class Coordinator {
        var hasRestoredWidth = false
        private var observation: NSObjectProtocol?
        private var debounceWork: DispatchWorkItem?

        func installObserver(on splitView: NSSplitView) {
            guard observation == nil, let sidebarView = splitView.subviews.first else { return }
            sidebarView.postsFrameChangedNotifications = true
            observation = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: sidebarView,
                queue: .main
            ) { [weak self] notification in
                guard let view = notification.object as? NSView else { return }
                let width = view.frame.width
                if width >= 200 {
                    self?.debounceSave(width: width)
                }
            }
        }

        private func debounceSave(width: CGFloat) {
            debounceWork?.cancel()
            let item = DispatchWorkItem {
                UserDefaults.standard.set(Double(width), forKey: "sidebarWidth")
            }
            debounceWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
        }

        deinit {
            if let observation {
                NotificationCenter.default.removeObserver(observation)
            }
            debounceWork?.cancel()
        }
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

// MARK: - WindowTabDropTarget

/// AppKit-level drop target for column drags onto window tabs.
/// Dropping a column header onto a window tab moves the column to that window.
/// Dropping onto the gap area (nil windowID) creates a new window.
private struct WindowTabDropTarget: NSViewRepresentable {
    let windowID: UUID?
    let paneManager: SplitPaneManager

    func makeNSView(context: Context) -> WindowTabDropView {
        let view = WindowTabDropView()
        view.windowID = windowID
        view.paneManager = paneManager
        return view
    }

    func updateNSView(_ nsView: WindowTabDropView, context: Context) {
        nsView.windowID = windowID
        nsView.paneManager = paneManager
    }

    final class WindowTabDropView: NSView {
        var windowID: UUID?
        var paneManager: SplitPaneManager?
        private var isHighlighted = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([WorktreeReference.pasteboardType])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        // Pass clicks through
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            // Only accept column drags (those with sourcePaneID)
            guard decodeColumnDrag(from: sender) != nil else { return [] }
            isHighlighted = true
            needsDisplay = true
            return .move
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            isHighlighted = false
            needsDisplay = true
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            isHighlighted = false
            needsDisplay = true

            guard let (ref, sourceColumnUUID) = decodeColumnDrag(from: sender),
                  let paneManager else { return false }

            // Don't move to same window
            if let windowID,
               let sourceWindow = paneManager.windows.first(where: { $0.columns.contains { $0.id == sourceColumnUUID } }),
               sourceWindow.id == windowID {
                return false
            }

            if let windowID {
                // Move to existing window
                paneManager.moveColumnToWindow(columnID: sourceColumnUUID, targetWindowID: windowID)
            } else {
                // Move to new window (gap area)
                paneManager.moveColumnToNewWindow(columnID: sourceColumnUUID)
            }
            return true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if isHighlighted {
                NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
            }
        }

        private func decodeColumnDrag(from info: NSDraggingInfo) -> (WorktreeReference, UUID)? {
            let pasteboard = info.draggingPasteboard
            var data = pasteboard.data(forType: WorktreeReference.pasteboardType)
            if data == nil, let item = pasteboard.pasteboardItems?.first {
                data = item.data(forType: WorktreeReference.pasteboardType)
            }
            guard let data,
                  let ref = try? JSONDecoder().decode(WorktreeReference.self, from: data),
                  let sourcePaneID = ref.sourcePaneID,
                  let sourceColumnUUID = UUID(uuidString: sourcePaneID) else {
                return nil
            }
            return (ref, sourceColumnUUID)
        }
    }
}
