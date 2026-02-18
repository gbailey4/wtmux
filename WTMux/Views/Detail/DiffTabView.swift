import SwiftUI
import WTCore
import WTDiff
import WTTerminal

struct DiffTabView: View {
    let window: WindowState
    let paneManager: SplitPaneManager
    let findWorktree: (String) -> Worktree?

    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id

    private var currentTheme: TerminalTheme {
        TerminalThemes.theme(forId: terminalThemeId)
    }

    private var worktreePath: String? {
        if case .diff(let path, _) = window.kind { return path }
        return nil
    }

    private var worktree: Worktree? {
        guard let path = worktreePath else { return nil }
        return findWorktree(path)
    }

    @Binding private var changedFileCount: Int

    init(window: WindowState, paneManager: SplitPaneManager, findWorktree: @escaping (String) -> Worktree?) {
        self.window = window
        self.paneManager = paneManager
        self.findWorktree = findWorktree
        self._changedFileCount = .constant(0)
    }

    var body: some View {
        HStack(spacing: 0) {
            if let file = window.diffFile {
                DiffContentView(
                    file: file,
                    onClose: { paneManager.closeDiffTab(windowID: window.id) },
                    backgroundColor: currentTheme.background.toColor(),
                    foregroundColor: currentTheme.foreground.toColor()
                ) {
                    if let worktreePath {
                        openInEditorMenu(relativePath: file.displayPath, worktreePath: worktreePath)
                    }
                }
                .environment(\.colorScheme, currentTheme.isDark ? .dark : .light)
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "doc.text",
                    description: Text("Select a file from the Changes panel.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let worktree {
                Divider()
                ChangesPanel(
                    worktree: worktree,
                    paneManager: paneManager,
                    paneID: window.diffSourcePaneID ?? UUID(),
                    changedFileCount: $changedFileCount
                )
                .frame(width: 400)
            }
        }
        .onKeyPress(.escape) {
            paneManager.closeDiffTab(windowID: window.id)
            return .handled
        }
        .background(currentTheme.background.toColor())
    }

    @ViewBuilder
    private func openInEditorMenu(relativePath: String, worktreePath: String) -> some View {
        let editors = ExternalEditor.installedEditors(custom: ExternalEditor.customEditors)
        Menu {
            ForEach(editors) { editor in
                Button(editor.name) {
                    let fileURL = URL(fileURLWithPath: worktreePath)
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
