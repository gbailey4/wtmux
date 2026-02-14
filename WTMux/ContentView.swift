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

    @State private var selectedWorktreeID: String?
    @State private var showingAddProject = false
    @State private var showRightPanel = false
    @State private var showRunnerPanel = false
    @State private var changedFileCount: Int = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var terminalSessionManager = TerminalSessionManager()
    @State private var claudeStatusManager = ClaudeStatusManager()
    @State private var importObserver = ProjectImportObserver()
    @State private var gitAvailable: Bool? = nil
    @State private var gitCheckDismissed = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                projects: projects,
                selectedWorktreeID: $selectedWorktreeID,
                showingAddProject: $showingAddProject,
                showRunnerPanel: $showRunnerPanel,
                terminalSessionManager: terminalSessionManager,
                claudeStatusManager: claudeStatusManager
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let selectedWorktreeID,
               let worktree = findWorktree(id: selectedWorktreeID) {
                WorktreeDetailView(
                    worktree: worktree,
                    terminalSessionManager: terminalSessionManager,
                    showRightPanel: $showRightPanel,
                    showRunnerPanel: $showRunnerPanel,
                    changedFileCount: $changedFileCount
                )
            } else {
                ContentUnavailableView(
                    "No Worktree Selected",
                    systemImage: "terminal",
                    description: Text("Select a worktree from the sidebar or add a project to get started.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showRightPanel.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .overlay(alignment: .topTrailing) {
                            if changedFileCount > 0 {
                                Text("\(changedFileCount)")
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
        }
        .safeAreaInset(edge: .top) {
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
                }
                .padding(10)
                .background(.yellow.opacity(0.15))
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .task {
            appDelegate.terminalSessionManager = terminalSessionManager
            await checkGitAvailability()
            backfillProjectColors()
            backfillSortOrders()
        }
        .sheet(isPresented: $showingAddProject) {
            AddProjectView(
                selectedWorktreeID: $selectedWorktreeID,
                terminalSessionManager: terminalSessionManager
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

    private func findWorktree(id: String) -> Worktree? {
        for project in projects {
            if let wt = project.worktrees.first(where: { $0.path == id }) {
                return wt
            }
        }
        return nil
    }
}
