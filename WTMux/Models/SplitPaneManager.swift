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
    var focusedColumnID: UUID?

    // MARK: - Diff Tabs

    func openDiffTab(file: DiffFile, worktreePath: String, branchName: String, fromColumn columnID: UUID) {
        // Search for existing diff tab for the same worktreePath
        if let existing = windows.first(where: {
            if case .diff(let path, _) = $0.kind { return path == worktreePath }
            return false
        }) {
            existing.diffFile = file
            existing.diffSourceColumnID = columnID
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
        newWindow.diffSourceColumnID = columnID
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

    var focusedColumn: WorktreeColumn? {
        guard let window = focusedWindow, let columnID = focusedColumnID else {
            return focusedWindow?.columns.first
        }
        return window.columns.first { $0.id == columnID } ?? window.columns.first
    }

    /// All worktree IDs currently visible in any column across all windows.
    var visibleWorktreeIDs: Set<String> {
        Set(windows.flatMap { $0.columns.compactMap(\.worktreeID) })
    }

    private static let stateKey = "splitPaneState"

    init() {
        if let (restoredWindows, focusedWinID, focusedColID) = Self.loadState() {
            self.windows = restoredWindows
            self.focusedWindowID = focusedWinID ?? restoredWindows.first?.id
            let focusedWin = restoredWindows.first { $0.id == self.focusedWindowID } ?? restoredWindows.first
            self.focusedColumnID = focusedColID ?? focusedWin?.columns.first?.id
        } else {
            self.windows = []
            self.focusedWindowID = nil
            self.focusedColumnID = nil
        }
    }

    func column(for id: UUID) -> WorktreeColumn? {
        for window in windows {
            if let col = window.columns.first(where: { $0.id == id }) {
                return col
            }
        }
        return nil
    }

    func column(forWorktreeID worktreeID: String, in window: WindowState? = nil) -> WorktreeColumn? {
        let searchWindow = window ?? focusedWindow
        return searchWindow?.columns.first { $0.worktreeID == worktreeID }
    }

    /// Focuses the first column (across all windows) that displays the given worktree.
    func focusColumn(containing worktreeID: String) {
        for window in windows {
            for column in window.columns where column.worktreeID == worktreeID {
                focusedWindowID = window.id
                focusedColumnID = column.id
                return
            }
        }
    }

    /// Searches all windows for a worktree, returning its location if found.
    func findWorktreeLocation(_ worktreeID: String) -> (windowID: UUID, columnID: UUID)? {
        for window in windows {
            for column in window.columns where column.worktreeID == worktreeID {
                return (windowID: window.id, columnID: column.id)
            }
        }
        return nil
    }

    /// Opens a worktree in a new window tab. If already open anywhere, focuses it instead.
    func openWorktreeInNewWindow(worktreeID: String) {
        if let loc = findWorktreeLocation(worktreeID) {
            focusedWindowID = loc.windowID
            focusedColumnID = loc.columnID
            return
        }
        let count = windows.count + 1
        let newColumn = WorktreeColumn(worktreeID: worktreeID)
        let newWindow = WindowState(name: "Window \(count)", columns: [newColumn])
        windows.append(newWindow)
        focusedWindowID = newWindow.id
        focusedColumnID = newColumn.id
        saveState()
    }

    /// Opens a worktree as a split in the current window. If already open anywhere, focuses it instead.
    func openWorktreeInCurrentWindowSplit(worktreeID: String) {
        if let loc = findWorktreeLocation(worktreeID) {
            focusedWindowID = loc.windowID
            focusedColumnID = loc.columnID
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
        focusedColumnID = column.id
        cleanupEmptyWindows()
        saveState()
    }

    /// Moves a column to an existing target window.
    func moveColumnToWindow(columnID: UUID, targetWindowID: UUID) {
        guard let sourceWindow = windows.first(where: { $0.columns.contains { $0.id == columnID } }),
              let colIndex = sourceWindow.columns.firstIndex(where: { $0.id == columnID }),
              let targetWindow = windows.first(where: { $0.id == targetWindowID }) else { return }

        // Check 5-column limit on target
        guard targetWindow.columns.count + 1 <= 5 else { return }

        let column = sourceWindow.columns[colIndex]
        sourceWindow.columns.remove(at: colIndex)

        targetWindow.columns.append(column)
        focusedWindowID = targetWindowID
        focusedColumnID = column.id
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
            focusedColumnID = nil
        }
    }

    func assignWorktree(_ worktreeID: String?, to columnID: UUID) {
        guard let col = column(for: columnID) else { return }
        col.worktreeID = worktreeID
        saveState()
    }

    func addColumn(worktreeID: String? = nil, after columnID: UUID? = nil) {
        guard let window = focusedWindow else { return }
        guard window.columns.count < 5 else { return }
        let newColumn = WorktreeColumn(worktreeID: worktreeID)
        if let afterID = columnID,
           let index = window.columns.firstIndex(where: { $0.id == afterID }) {
            window.columns.insert(newColumn, at: index + 1)
        } else {
            window.columns.append(newColumn)
        }
        focusedColumnID = newColumn.id
        saveState()
    }

    func splitRight(worktreeID: String? = nil) {
        guard let window = focusedWindow else { return }

        // If worktreeID matches focused column, create new column with same worktree
        if let wid = worktreeID, let focused = focusedColumn, focused.worktreeID == wid {
            addColumn(worktreeID: wid, after: focused.id)
            return
        }

        // If worktreeID already has a column in this window, focus it
        if let wid = worktreeID, let existingCol = column(forWorktreeID: wid, in: window) {
            focusedColumnID = existingCol.id
            return
        }

        // Otherwise create new column after focused column
        addColumn(worktreeID: worktreeID, after: focusedColumn?.id)
    }

    /// Opens a worktree in a split. If already visible in the current window, focuses it.
    /// If visible in another window, focuses it. Otherwise creates a new column.
    func openInSplit(worktreeID: String) {
        guard let window = focusedWindow else { return }

        // If worktree is already visible in this window, focus that column
        if let existingCol = window.columns.first(where: { $0.worktreeID == worktreeID }) {
            focusedColumnID = existingCol.id
            return
        }

        // If visible in another window, focus it there
        if let loc = findWorktreeLocation(worktreeID) {
            focusedWindowID = loc.windowID
            focusedColumnID = loc.columnID
            return
        }

        // Not visible anywhere — create new column
        addColumn(worktreeID: worktreeID, after: focusedColumn?.id)
    }

    func removeColumn(id: UUID) {
        guard let window = focusedWindow,
              let colIndex = window.columns.firstIndex(where: { $0.id == id }) else { return }

        let column = window.columns[colIndex]
        let worktreeID = column.worktreeID

        if window.columns.count == 1 {
            // Last column in window — remove the entire window
            terminalSessionManager?.terminateSessionsForColumn(column.id.uuidString)
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
            terminalSessionManager?.terminateSessionsForColumn(column.id.uuidString)
            window.columns.remove(at: colIndex)
            if focusedColumnID == id {
                let newColIndex = min(max(0, colIndex - 1), window.columns.count - 1)
                focusedColumnID = window.columns.isEmpty ? nil : window.columns[newColIndex].id
            }
            if let worktreeID, !visibleWorktreeIDs.contains(worktreeID) {
                terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
            }
        }
        saveState()
    }

    func closeFocusedColumn() {
        guard let id = focusedColumnID else { return }
        removeColumn(id: id)
    }

    func focusNextColumn() {
        guard let window = focusedWindow else { return }
        let allColumns = window.columns
        guard let currentID = focusedColumnID,
              let index = allColumns.firstIndex(where: { $0.id == currentID }) else { return }
        let nextIndex = (index + 1) % allColumns.count
        focusedColumnID = allColumns[nextIndex].id
    }

    func focusPreviousColumn() {
        guard let window = focusedWindow else { return }
        let allColumns = window.columns
        guard let currentID = focusedColumnID,
              let index = allColumns.firstIndex(where: { $0.id == currentID }) else { return }
        let prevIndex = (index - 1 + allColumns.count) % allColumns.count
        focusedColumnID = allColumns[prevIndex].id
    }

    // MARK: - Move Operations (preserves column IDs and terminal sessions)

    /// Repositions a column within the focused window without destroying it.
    func moveColumn(id: UUID, toIndex: Int) {
        guard let window = focusedWindow,
              let fromIndex = window.columns.firstIndex(where: { $0.id == id }) else { return }
        let column = window.columns.remove(at: fromIndex)
        let clampedIndex = max(0, min(toIndex, window.columns.count))
        window.columns.insert(column, at: clampedIndex)
        saveState()
    }

    func insertColumn(worktreeID: String?, at index: Int) {
        guard let window = focusedWindow else { return }
        guard window.columns.count < 5 else { return }
        let newColumn = WorktreeColumn(worktreeID: worktreeID)
        let clampedIndex = max(0, min(index, window.columns.count))
        window.columns.insert(newColumn, at: clampedIndex)
        focusedColumnID = newColumn.id
        saveState()
    }

    // MARK: - Tab Fluidity (move tabs between columns)

    /// Extracts a terminal tab from its current column into a new column at the given index.
    func extractTabToNewColumn(sessionId: String, fromColumnId: UUID, atIndex: Int) {
        guard let window = focusedWindow,
              window.columns.count < 5,
              let sourceColumn = column(for: fromColumnId),
              let tsm = terminalSessionManager else { return }

        // Create a new column with the same worktree
        let newColumn = WorktreeColumn(worktreeID: sourceColumn.worktreeID)
        let clampedIndex = max(0, min(atIndex, window.columns.count))
        window.columns.insert(newColumn, at: clampedIndex)

        // Move the session to the new column
        tsm.moveSession(sessionId: sessionId, fromColumn: fromColumnId.uuidString, toColumn: newColumn.id.uuidString)

        // If source column has no more tabs, remove it
        if tsm.orderedSessions(forColumn: fromColumnId.uuidString).isEmpty {
            window.columns.removeAll { $0.id == fromColumnId }
        }

        focusedColumnID = newColumn.id
        saveState()
    }

    /// Moves a terminal tab from one column to another existing column.
    func moveTabToColumn(sessionId: String, fromColumnId: UUID, toColumnId: UUID) {
        guard let tsm = terminalSessionManager,
              fromColumnId != toColumnId else { return }

        tsm.moveSession(sessionId: sessionId, fromColumn: fromColumnId.uuidString, toColumn: toColumnId.uuidString)

        // If source column has no more tabs, remove it
        if let window = focusedWindow,
           tsm.orderedSessions(forColumn: fromColumnId.uuidString).isEmpty {
            window.columns.removeAll { $0.id == fromColumnId }
            if focusedColumnID == fromColumnId {
                focusedColumnID = toColumnId
            }
        }

        focusedColumnID = toColumnId
        saveState()
    }

    /// Clears a worktree from all columns that display it (across all windows).
    /// Windows left with no columns are removed entirely.
    func clearWorktree(_ worktreeID: String) {
        for window in windows {
            for column in window.columns where column.worktreeID == worktreeID {
                terminalSessionManager?.terminateSessionsForColumn(column.id.uuidString)
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
            focusedColumnID = nil
        } else if let window = focusedWindow,
                  !window.columns.contains(where: { $0.id == focusedColumnID }) {
            focusedColumnID = window.columns.first?.id
        } else if focusedWindow == nil {
            // Focused window was removed — pick the first remaining
            focusedWindowID = windows.first?.id
            focusedColumnID = windows.first?.columns.first?.id
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
                terminalSessionManager?.terminateSessionsForColumn(column.id.uuidString)
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
                focusedColumnID = nil
            } else {
                let newIndex = min(index, windows.count - 1)
                focusedWindowID = windows[newIndex].id
                focusedColumnID = windows[newIndex].columns.first?.id
            }
        }
        saveState()
    }

    func focusWindow(id: UUID) {
        guard let window = windows.first(where: { $0.id == id }) else { return }
        focusedWindowID = id
        focusedColumnID = window.columns.first?.id
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
        let focusedColumnID: String?
        // Legacy field for decoding compat
        let focusedPaneID: String?

        init(windows: [WindowSaved], focusedWindowID: String?, focusedColumnID: String?) {
            self.windows = windows
            self.focusedWindowID = focusedWindowID
            self.focusedColumnID = focusedColumnID
            self.focusedPaneID = nil
        }
    }

    private struct WindowSaved: Codable {
        let id: String
        let name: String
        let columns: [ColumnSaved]
    }

    private struct ColumnSaved: Codable {
        let id: String
        let worktreeID: String?
        let showRunnerPanel: Bool
        // Legacy field for decoding compat
        let paneCount: Int?

        init(id: String, worktreeID: String?, showRunnerPanel: Bool) {
            self.id = id
            self.worktreeID = worktreeID
            self.showRunnerPanel = showRunnerPanel
            self.paneCount = nil
        }
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
                            showRunnerPanel: col.showRunnerPanel
                        )
                    }
                )
            },
            focusedWindowID: focusedWindowID?.uuidString,
            focusedColumnID: focusedColumnID?.uuidString
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    private static func loadState() -> ([WindowState], UUID?, UUID?)? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }

        // Try current format
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
                        WorktreeColumn(
                            id: UUID(uuidString: col.id) ?? UUID(),
                            worktreeID: col.worktreeID,
                            showRunnerPanel: col.showRunnerPanel
                        )
                    }
                )
            }
            let focusedWinID = state.focusedWindowID.flatMap { UUID(uuidString: $0) }
            // Prefer focusedColumnID, fall back to focusedPaneID for migration
            let focusedColID = (state.focusedColumnID ?? state.focusedPaneID).flatMap { UUID(uuidString: $0) }
            return (windows, focusedWinID, focusedColID)
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
            return (windows, focusedWinID, nil)
        }

        // Migrate from old flat format (single window)
        struct OldFlatState: Codable {
            let worktreeIDs: [String?]
        }
        if let flat = try? JSONDecoder().decode(OldFlatState.self, from: data), !flat.worktreeIDs.isEmpty {
            let columns = flat.worktreeIDs.map { WorktreeColumn(worktreeID: $0) }
            let window = WindowState(name: "Window 1", columns: columns)
            return ([window], window.id, window.columns.first?.id)
        }

        return nil
    }
}
