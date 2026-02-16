import Foundation
import WTDiff
import WTTerminal

@MainActor @Observable
final class SplitPaneManager {
    weak var terminalSessionManager: TerminalSessionManager?

    var windows: [WindowState] {
        didSet { saveState() }
    }
    var focusedWindowID: UUID?
    var focusedPaneID: UUID?

    // MARK: - Diff Tabs

    func openDiffTab(file: DiffFile, worktreePath: String, branchName: String, fromPane paneID: UUID) {
        // Search for existing diff tab for the same worktreePath
        if let existing = windows.first(where: {
            if case .diff(let path, _) = $0.kind { return path == worktreePath }
            return false
        }) {
            existing.diffFile = file
            existing.diffSourcePaneID = paneID
            focusedWindowID = existing.id
            return
        }

        // Create new diff tab
        let projectName = worktreePath.components(separatedBy: "/").last ?? "Unknown"
        let newWindow = WindowState(
            name: "Diff \u{2014} \(projectName) / \(branchName)",
            columns: [],
            kind: .diff(worktreePath: worktreePath, branchName: branchName)
        )
        newWindow.diffFile = file
        newWindow.diffSourcePaneID = paneID
        windows.append(newWindow)
        focusedWindowID = newWindow.id
    }

    func closeDiffTab(windowID: UUID) {
        removeWindow(id: windowID)
    }

    var focusedWindow: WindowState? {
        guard let id = focusedWindowID else { return windows.first }
        return windows.first { $0.id == id } ?? windows.first
    }

    var columns: [WorktreeColumn] {
        focusedWindow?.columns ?? []
    }

    /// Flat list of all panes in the focused window (across all columns).
    var panes: [PaneState] {
        focusedWindow?.columns.flatMap(\.panes) ?? []
    }

    /// The column containing the focused pane.
    var focusedColumn: WorktreeColumn? {
        guard let window = focusedWindow, let paneID = focusedPaneID else {
            return focusedWindow?.columns.first
        }
        return window.columns.first { col in
            col.panes.contains { $0.id == paneID }
        } ?? window.columns.first
    }

    var focusedPane: PaneState? {
        guard let win = focusedWindow else { return nil }
        let allPanes = win.columns.flatMap(\.panes)
        guard let id = focusedPaneID else { return allPanes.first }
        return allPanes.first { $0.id == id } ?? allPanes.first
    }

    /// All worktree IDs currently visible in any column across all windows.
    var visibleWorktreeIDs: Set<String> {
        Set(windows.flatMap { $0.columns.compactMap(\.worktreeID) })
    }

    private static let stateKey = "splitPaneState"

    init() {
        if let (restoredWindows, focusedWinID, _) = Self.loadState() {
            self.windows = restoredWindows
            self.focusedWindowID = focusedWinID ?? restoredWindows.first?.id
            // Pane IDs are regenerated on restore, so always default to first pane
            let focusedWin = restoredWindows.first { $0.id == self.focusedWindowID } ?? restoredWindows.first
            self.focusedPaneID = focusedWin?.columns.first?.panes.first?.id
        } else {
            self.windows = []
            self.focusedWindowID = nil
            self.focusedPaneID = nil
        }
    }

    func pane(for id: UUID) -> PaneState? {
        for window in windows {
            for column in window.columns {
                if let pane = column.panes.first(where: { $0.id == id }) {
                    return pane
                }
            }
        }
        return nil
    }

    func column(for id: UUID) -> WorktreeColumn? {
        for window in windows {
            if let col = window.columns.first(where: { $0.id == id }) {
                return col
            }
        }
        return nil
    }

    func column(forPane paneID: UUID) -> WorktreeColumn? {
        for window in windows {
            for column in window.columns {
                if column.panes.contains(where: { $0.id == paneID }) {
                    return column
                }
            }
        }
        return nil
    }

    func column(forWorktreeID worktreeID: String, in window: WindowState? = nil) -> WorktreeColumn? {
        let searchWindow = window ?? focusedWindow
        return searchWindow?.columns.first { $0.worktreeID == worktreeID }
    }

    /// Focuses the first pane (across all windows) that displays the given worktree.
    func focusPane(containing worktreeID: String) {
        for window in windows {
            for column in window.columns where column.worktreeID == worktreeID {
                if let pane = column.panes.first {
                    focusedWindowID = window.id
                    focusedPaneID = pane.id
                    return
                }
            }
        }
    }

    /// Searches all windows for a worktree, returning its location if found.
    func findWorktreeLocation(_ worktreeID: String) -> (windowID: UUID, columnID: UUID, paneID: UUID)? {
        for window in windows {
            for column in window.columns where column.worktreeID == worktreeID {
                if let pane = column.panes.first {
                    return (windowID: window.id, columnID: column.id, paneID: pane.id)
                }
            }
        }
        return nil
    }

    /// Opens a worktree in a new window tab. If already open anywhere, focuses it instead.
    func openWorktreeInNewWindow(worktreeID: String) {
        if let loc = findWorktreeLocation(worktreeID) {
            focusedWindowID = loc.windowID
            focusedPaneID = loc.paneID
            return
        }
        let count = windows.count + 1
        let newColumn = WorktreeColumn(worktreeID: worktreeID)
        let newWindow = WindowState(name: "Window \(count)", columns: [newColumn])
        windows.append(newWindow)
        focusedWindowID = newWindow.id
        focusedPaneID = newColumn.panes.first?.id
        saveState()
    }

    /// Opens a worktree as a split in the current window. If already open anywhere, focuses it instead.
    func openWorktreeInCurrentWindowSplit(worktreeID: String) {
        if let loc = findWorktreeLocation(worktreeID) {
            focusedWindowID = loc.windowID
            focusedPaneID = loc.paneID
            return
        }
        addColumn(worktreeID: worktreeID, after: focusedColumn?.id)
    }

    /// Moves a column to a new window tab.
    func moveColumnToNewWindow(columnID: UUID) {
        guard let sourceWindow = windows.first(where: { $0.columns.contains { $0.id == columnID } }),
              let colIndex = sourceWindow.columns.firstIndex(where: { $0.id == columnID }) else { return }

        let column = sourceWindow.columns[colIndex]
        sourceWindow.columns.remove(at: colIndex)

        let count = windows.count + 1
        let newWindow = WindowState(name: "Window \(count)", columns: [column])
        windows.append(newWindow)
        focusedWindowID = newWindow.id
        focusedPaneID = column.panes.first?.id
        cleanupEmptyWindows()
        saveState()
    }

    /// Moves a column to an existing target window.
    func moveColumnToWindow(columnID: UUID, targetWindowID: UUID) {
        guard let sourceWindow = windows.first(where: { $0.columns.contains { $0.id == columnID } }),
              let colIndex = sourceWindow.columns.firstIndex(where: { $0.id == columnID }),
              let targetWindow = windows.first(where: { $0.id == targetWindowID }) else { return }

        // Check 5-pane limit on target
        let targetPaneCount = targetWindow.columns.flatMap(\.panes).count
        let movingPaneCount = sourceWindow.columns[colIndex].panes.count
        guard targetPaneCount + movingPaneCount <= 5 else { return }

        let column = sourceWindow.columns[colIndex]
        sourceWindow.columns.remove(at: colIndex)

        targetWindow.columns.append(column)
        focusedWindowID = targetWindowID
        focusedPaneID = column.panes.first?.id
        cleanupEmptyWindows()
        saveState()
    }

    /// Removes windows that have only empty columns (no worktreeID), unless it's the focused window.
    private func cleanupEmptyWindows() {
        windows.removeAll { window in
            window.id != focusedWindowID
                && window.columns.allSatisfy({ $0.worktreeID == nil })
        }
        if windows.isEmpty {
            focusedWindowID = nil
            focusedPaneID = nil
        }
    }

    func assignWorktree(_ worktreeID: String?, to paneID: UUID) {
        guard let col = column(forPane: paneID) else { return }
        col.worktreeID = worktreeID
        saveState()
    }

    func addColumn(worktreeID: String? = nil, after columnID: UUID? = nil) {
        guard let window = focusedWindow else { return }
        let totalPanes = window.columns.flatMap(\.panes).count
        guard totalPanes < 5 else { return }
        let newColumn = WorktreeColumn(worktreeID: worktreeID)
        if let afterID = columnID,
           let index = window.columns.firstIndex(where: { $0.id == afterID }) {
            window.columns.insert(newColumn, at: index + 1)
        } else {
            window.columns.append(newColumn)
        }
        focusedPaneID = newColumn.panes.first?.id
        saveState()
    }

    func splitRight(worktreeID: String? = nil) {
        guard let window = focusedWindow else { return }

        // If worktreeID matches focused column, add pane to same column (same-worktree split)
        if let wid = worktreeID, let focused = focusedColumn, focused.worktreeID == wid {
            splitSameWorktree()
            return
        }

        // If worktreeID already has a column in this window, focus it
        if let wid = worktreeID, let existingCol = column(forWorktreeID: wid, in: window) {
            if let pane = existingCol.panes.first {
                focusedPaneID = pane.id
            }
            return
        }

        // Otherwise create new column after focused column
        addColumn(worktreeID: worktreeID, after: focusedColumn?.id)
    }

    /// Adds a new pane to the focused column (same-worktree split).
    func splitSameWorktree() {
        guard let column = focusedColumn, let window = focusedWindow else { return }
        let totalPanes = window.columns.flatMap(\.panes).count
        guard totalPanes < 5 else { return }
        let newPane = PaneState()
        column.panes.append(newPane)
        focusedPaneID = newPane.id
        saveState()
    }

    /// Opens a worktree in a split. If already visible in the current window, adds a pane.
    /// If visible in another window, focuses it. Otherwise creates a new column.
    func openInSplit(worktreeID: String) {
        guard let window = focusedWindow else { return }

        // If worktree is already visible in this window, add pane to that column
        if let existingCol = window.columns.first(where: { $0.worktreeID == worktreeID }) {
            let totalPanes = window.columns.flatMap(\.panes).count
            guard totalPanes < 5 else { return }
            let newPane = PaneState()
            existingCol.panes.append(newPane)
            focusedPaneID = newPane.id
            saveState()
            return
        }

        // If visible in another window, focus it there
        if let loc = findWorktreeLocation(worktreeID) {
            focusedWindowID = loc.windowID
            focusedPaneID = loc.paneID
            return
        }

        // Not visible anywhere — create new column
        addColumn(worktreeID: worktreeID, after: focusedColumn?.id)
    }

    func removePane(id: UUID) {
        guard let window = focusedWindow,
              let colIndex = window.columns.firstIndex(where: { $0.panes.contains { $0.id == id } }),
              let paneIndex = window.columns[colIndex].panes.firstIndex(where: { $0.id == id }) else { return }

        let column = window.columns[colIndex]

        if column.panes.count == 1 {
            // Last pane in column — remove the entire column
            let worktreeID = column.worktreeID

            if window.columns.count == 1 {
                // Last column in window — remove the entire window
                terminalSessionManager?.terminateSessionsForPane(column.panes[0].id.uuidString)
                if let worktreeID {
                    let othersHaveIt = windows.contains { w in
                        w.id != window.id && w.columns.contains { $0.worktreeID == worktreeID }
                    }
                    if !othersHaveIt {
                        terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
                    }
                }
                removeWindow(id: window.id)
                return
            } else {
                terminalSessionManager?.terminateSessionsForPane(column.panes[0].id.uuidString)
                window.columns.remove(at: colIndex)
                if focusedPaneID == id {
                    let newColIndex = min(max(0, colIndex - 1), window.columns.count - 1)
                    focusedPaneID = window.columns.isEmpty ? nil : window.columns[newColIndex].panes.first?.id
                }
                if let worktreeID, !visibleWorktreeIDs.contains(worktreeID) {
                    terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
                }
            }
        } else {
            // Multiple panes in column — just remove this pane
            terminalSessionManager?.terminateSessionsForPane(id.uuidString)
            column.panes.remove(at: paneIndex)
            if focusedPaneID == id {
                let newIndex = min(max(0, paneIndex - 1), column.panes.count - 1)
                focusedPaneID = column.panes.isEmpty ? nil : column.panes[newIndex].id
            }
        }
        saveState()
    }

    func closeFocusedPane() {
        guard let id = focusedPaneID else { return }
        removePane(id: id)
    }

    func focusNextPane() {
        guard let window = focusedWindow else { return }
        let allPanes = window.columns.flatMap(\.panes)
        guard let currentID = focusedPaneID,
              let index = allPanes.firstIndex(where: { $0.id == currentID }) else { return }
        let nextIndex = (index + 1) % allPanes.count
        focusedPaneID = allPanes[nextIndex].id
    }

    func focusPreviousPane() {
        guard let window = focusedWindow else { return }
        let allPanes = window.columns.flatMap(\.panes)
        guard let currentID = focusedPaneID,
              let index = allPanes.firstIndex(where: { $0.id == currentID }) else { return }
        let prevIndex = (index - 1 + allPanes.count) % allPanes.count
        focusedPaneID = allPanes[prevIndex].id
    }

    // MARK: - Move Operations (preserves pane IDs and terminal sessions)

    /// Repositions a column within the focused window without destroying it.
    func moveColumn(id: UUID, toIndex: Int) {
        guard let window = focusedWindow,
              let fromIndex = window.columns.firstIndex(where: { $0.id == id }) else { return }
        let column = window.columns.remove(at: fromIndex)
        let clampedIndex = max(0, min(toIndex, window.columns.count))
        window.columns.insert(column, at: clampedIndex)
        saveState()
    }

    /// Extracts a pane from a multi-pane column into a new single-pane column at the given index.
    /// The pane's UUID is preserved, keeping terminal sessions alive.
    func extractPaneToColumn(paneID: UUID, at index: Int) {
        guard let window = focusedWindow,
              let sourceCol = window.columns.first(where: { $0.panes.contains { $0.id == paneID } }),
              sourceCol.panes.count > 1,
              let paneIndex = sourceCol.panes.firstIndex(where: { $0.id == paneID }) else { return }

        let pane = sourceCol.panes.remove(at: paneIndex)
        let newColumn = WorktreeColumn(worktreeID: sourceCol.worktreeID, panes: [pane])
        let clampedIndex = max(0, min(index, window.columns.count))
        window.columns.insert(newColumn, at: clampedIndex)
        focusedPaneID = pane.id
        saveState()
    }

    /// Moves a pane to an existing target column. Removes the source column if left empty.
    /// The pane's UUID is preserved, keeping terminal sessions alive.
    func movePaneToColumn(paneID: UUID, targetColumnID: UUID) {
        guard let window = focusedWindow,
              let sourceCol = window.columns.first(where: { $0.panes.contains { $0.id == paneID } }),
              let targetCol = window.columns.first(where: { $0.id == targetColumnID }),
              sourceCol.id != targetCol.id,
              let paneIndex = sourceCol.panes.firstIndex(where: { $0.id == paneID }) else { return }

        let pane = sourceCol.panes.remove(at: paneIndex)
        targetCol.panes.append(pane)

        // If source column is now empty, remove it
        if sourceCol.panes.isEmpty {
            window.columns.removeAll { $0.id == sourceCol.id }
        }

        focusedPaneID = pane.id
        saveState()
    }

    func insertColumn(worktreeID: String?, at index: Int) {
        guard let window = focusedWindow else { return }
        let totalPanes = window.columns.flatMap(\.panes).count
        guard totalPanes < 5 else { return }
        let newColumn = WorktreeColumn(worktreeID: worktreeID)
        let clampedIndex = max(0, min(index, window.columns.count))
        window.columns.insert(newColumn, at: clampedIndex)
        focusedPaneID = newColumn.panes.first?.id
        saveState()
    }

    /// Clears a worktree from all columns that display it (across all windows).
    /// Windows left with no columns are removed entirely.
    func clearWorktree(_ worktreeID: String) {
        for window in windows {
            for column in window.columns where column.worktreeID == worktreeID {
                for pane in column.panes {
                    terminalSessionManager?.terminateSessionsForPane(pane.id.uuidString)
                }
            }
            window.columns.removeAll { $0.worktreeID == worktreeID }
        }
        // Remove worktree windows that now have no columns, and diff windows for this worktree
        windows.removeAll { window in
            if case .diff(let path, _) = window.kind, path == worktreeID {
                return true
            }
            return window.columns.isEmpty && {
                if case .worktrees = window.kind { return true }
                return false
            }()
        }
        terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
        // Update focus
        if windows.isEmpty {
            focusedWindowID = nil
            focusedPaneID = nil
        } else if let window = focusedWindow,
                  !window.columns.flatMap(\.panes).contains(where: { $0.id == focusedPaneID }) {
            focusedPaneID = window.columns.first?.panes.first?.id
        } else if focusedWindow == nil {
            // Focused window was removed — pick the first remaining
            focusedWindowID = windows.first?.id
            focusedPaneID = windows.first?.columns.first?.panes.first?.id
        }
        saveState()
    }

    // MARK: - Window Management

    func addWindow() {
        let count = windows.count + 1
        let newWindow = WindowState(name: "Window \(count)", columns: [WorktreeColumn()])
        windows.append(newWindow)
        focusWindow(id: newWindow.id)
        saveState()
    }

    func removeWindow(id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let window = windows[index]
        // Only clean up terminal sessions for worktree windows (diff tabs have no sessions)
        if case .worktrees = window.kind {
            for column in window.columns {
                for pane in column.panes {
                    terminalSessionManager?.terminateSessionsForPane(pane.id.uuidString)
                }
                if let worktreeID = column.worktreeID {
                    let othersHaveIt = windows.contains { w in
                        w.id != id && w.columns.contains { $0.worktreeID == worktreeID }
                    }
                    if !othersHaveIt {
                        terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
                    }
                }
            }
        }
        windows.remove(at: index)
        if focusedWindowID == id {
            if windows.isEmpty {
                focusedWindowID = nil
                focusedPaneID = nil
            } else {
                let newIndex = min(index, windows.count - 1)
                focusedWindowID = windows[newIndex].id
                focusedPaneID = windows[newIndex].columns.first?.panes.first?.id
            }
        }
        saveState()
    }

    func focusWindow(id: UUID) {
        guard let window = windows.first(where: { $0.id == id }) else { return }
        focusedWindowID = id
        focusedPaneID = window.columns.first?.panes.first?.id
        saveState()
    }

    func renameWindow(id: UUID, name: String) {
        guard !name.isEmpty, let window = windows.first(where: { $0.id == id }) else { return }
        window.name = name
        saveState()
    }

    // MARK: - Persistence

    private struct SavedState: Codable {
        let windows: [WindowSaved]
        let focusedWindowID: String?
        // focusedPaneID kept for decoding compat but not used — pane IDs are regenerated on restore
        let focusedPaneID: String?
    }

    private struct WindowSaved: Codable {
        let id: String
        let name: String
        let columns: [ColumnSaved]
    }

    private struct ColumnSaved: Codable {
        let id: String
        let worktreeID: String?
        let paneCount: Int
        let showRunnerPanel: Bool
    }

    private func saveState() {
        let worktreeWindows = windows.filter {
            if case .worktrees = $0.kind { return true }
            return false
        }
        let state = SavedState(
            windows: worktreeWindows.map { w in
                WindowSaved(
                    id: w.id.uuidString,
                    name: w.name,
                    columns: w.columns.map { col in
                        ColumnSaved(
                            id: col.id.uuidString,
                            worktreeID: col.worktreeID,
                            paneCount: col.panes.count,
                            showRunnerPanel: col.showRunnerPanel
                        )
                    }
                )
            },
            focusedWindowID: focusedWindowID?.uuidString,
            focusedPaneID: nil
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    private static func loadState() -> ([WindowState], UUID?, UUID?)? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }

        // Try new column-based format
        if let state = try? JSONDecoder().decode(SavedState.self, from: data) {
            // Valid saved state with 0 windows — restore empty state
            if state.windows.isEmpty {
                return ([], nil, nil)
            }
            guard state.windows.first?.columns.isEmpty == false else {
                // Fall through to legacy formats below
                return nil
            }
            let windows = state.windows.map { w in
                WindowState(
                    id: UUID(uuidString: w.id) ?? UUID(),
                    name: w.name,
                    columns: w.columns.map { col in
                        let panes = (0..<max(1, col.paneCount)).map { _ in PaneState() }
                        return WorktreeColumn(
                            id: UUID(uuidString: col.id) ?? UUID(),
                            worktreeID: col.worktreeID,
                            panes: panes,
                            showRunnerPanel: col.showRunnerPanel
                        )
                    }
                )
            }
            let focusedWinID = state.focusedWindowID.flatMap { UUID(uuidString: $0) }
            let focusedPaneID = state.focusedPaneID.flatMap { UUID(uuidString: $0) }
            return (windows, focusedWinID, focusedPaneID)
        }

        // Migrate from old window-based flat format (worktreeIDs per window)
        struct LegacyWindowSaved: Codable {
            let id: String
            let name: String
            let worktreeIDs: [String?]
        }
        struct LegacyState: Codable {
            let windows: [LegacyWindowSaved]
            let focusedWindowID: String?
            let focusedPaneID: String?
        }
        if let legacy = try? JSONDecoder().decode(LegacyState.self, from: data), !legacy.windows.isEmpty {
            let windows = legacy.windows.map { w in
                WindowState(
                    id: UUID(uuidString: w.id) ?? UUID(),
                    name: w.name,
                    columns: w.worktreeIDs.map { wtId in
                        WorktreeColumn(worktreeID: wtId)
                    }
                )
            }
            let focusedWinID = legacy.focusedWindowID.flatMap { UUID(uuidString: $0) }
            let focusedPaneID = legacy.focusedPaneID.flatMap { UUID(uuidString: $0) }
            return (windows, focusedWinID, focusedPaneID)
        }

        // Migrate from old flat format (single window)
        struct OldFlatState: Codable {
            let worktreeIDs: [String?]
        }
        if let flat = try? JSONDecoder().decode(OldFlatState.self, from: data), !flat.worktreeIDs.isEmpty {
            let columns = flat.worktreeIDs.map { WorktreeColumn(worktreeID: $0) }
            let window = WindowState(name: "Window 1", columns: columns)
            return ([window], window.id, window.columns.first?.panes.first?.id)
        }

        return nil
    }
}
