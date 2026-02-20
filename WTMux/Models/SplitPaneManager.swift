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
    var pendingLabelPaneID: UUID?

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
            panes: [],
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

    var panes: [WorktreePane] {
        focusedWindow?.panes ?? []
    }

    var expandedPanes: [WorktreePane] {
        focusedWindow?.panes.filter { !$0.isMinimized } ?? []
    }

    var minimizedPanes: [WorktreePane] {
        focusedWindow?.panes.filter { $0.isMinimized } ?? []
    }

    var focusedPane: WorktreePane? {
        guard let window = focusedWindow, let paneID = focusedPaneID else {
            return focusedWindow?.panes.first { !$0.isMinimized }
        }
        let p = window.panes.first { $0.id == paneID }
        if let p, p.isMinimized {
            return window.panes.first { !$0.isMinimized }
        }
        return p ?? window.panes.first { !$0.isMinimized }
    }

    /// All worktree IDs currently visible in any pane across all windows.
    var visibleWorktreeIDs: Set<String> {
        Set(windows.flatMap { $0.panes.compactMap(\.worktreeID) })
    }

    /// Returns the shared worktree ID when all expanded panes in the focused window display the same worktree
    /// and there are 2+ expanded panes. Returns nil otherwise.
    var sharedWorktreeID: String? {
        let expanded = expandedPanes
        guard expanded.count >= 2 else { return nil }
        let ids = expanded.compactMap(\.worktreeID)
        guard ids.count == expanded.count else { return nil }
        let unique = Set(ids)
        return unique.count == 1 ? unique.first : nil
    }

    private static let stateKey = "splitPaneState"

    init() {
        if let (restoredWindows, focusedWinID, focusedPID) = Self.loadState() {
            self.windows = restoredWindows
            self.focusedWindowID = focusedWinID ?? restoredWindows.first?.id
            let focusedWin = restoredWindows.first { $0.id == self.focusedWindowID } ?? restoredWindows.first
            self.focusedPaneID = focusedPID ?? focusedWin?.panes.first?.id
        } else {
            self.windows = []
            self.focusedWindowID = nil
            self.focusedPaneID = nil
        }
    }

    func pane(for id: UUID) -> WorktreePane? {
        for window in windows {
            if let p = window.panes.first(where: { $0.id == id }) {
                return p
            }
        }
        return nil
    }

    func pane(forWorktreeID worktreeID: String, in window: WindowState? = nil) -> WorktreePane? {
        let searchWindow = window ?? focusedWindow
        return searchWindow?.panes.first { $0.worktreeID == worktreeID }
    }

    /// Focuses the first pane (across all windows) that displays the given worktree.
    func focusPane(containing worktreeID: String) {
        for window in windows {
            for pane in window.panes where pane.worktreeID == worktreeID {
                focusedWindowID = window.id
                focusedPaneID = pane.id
                return
            }
        }
    }

    /// Searches all windows for a worktree, returning its location if found.
    func findWorktreeLocation(_ worktreeID: String) -> (windowID: UUID, paneID: UUID)? {
        for window in windows {
            for pane in window.panes where pane.worktreeID == worktreeID {
                return (windowID: window.id, paneID: pane.id)
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
        let newPane = WorktreePane(worktreeID: worktreeID)
        let newWindow = WindowState(name: "Window \(count)", panes: [newPane])
        windows.append(newWindow)
        focusedWindowID = newWindow.id
        focusedPaneID = newPane.id
        markPendingLabel(newPane.id)
        saveState()
    }

    /// Opens a worktree as a split in the current window. If already open anywhere, focuses it instead.
    func openWorktreeInCurrentWindowSplit(worktreeID: String) {
        if let loc = findWorktreeLocation(worktreeID) {
            focusedWindowID = loc.windowID
            focusedPaneID = loc.paneID
            return
        }
        addPane(worktreeID: worktreeID, after: focusedPane?.id)
    }

    /// Moves a pane to a new window tab.
    func movePaneToNewWindow(paneID: UUID) {
        guard let sourceWindow = windows.first(where: { $0.panes.contains { $0.id == paneID } }),
              let paneIndex = sourceWindow.panes.firstIndex(where: { $0.id == paneID }) else { return }

        let p = sourceWindow.panes[paneIndex]
        sourceWindow.panes.remove(at: paneIndex)

        let count = windows.count + 1
        let newWindow = WindowState(name: "Window \(count)", panes: [p])
        windows.append(newWindow)
        focusedWindowID = newWindow.id
        focusedPaneID = p.id
        cleanupEmptyWindows()
        saveState()
    }

    /// Moves a pane to an existing target window.
    func movePaneToWindow(paneID: UUID, targetWindowID: UUID) {
        guard let sourceWindow = windows.first(where: { $0.panes.contains { $0.id == paneID } }),
              let paneIndex = sourceWindow.panes.firstIndex(where: { $0.id == paneID }),
              let targetWindow = windows.first(where: { $0.id == targetWindowID }) else { return }

        // Check 5-pane limit on target
        guard targetWindow.panes.count + 1 <= 5 else { return }

        let p = sourceWindow.panes[paneIndex]
        sourceWindow.panes.remove(at: paneIndex)

        targetWindow.panes.append(p)
        focusedWindowID = targetWindowID
        focusedPaneID = p.id
        cleanupEmptyWindows()
        saveState()
    }

    /// Moves the focused pane to the next window.
    func movePaneToNextWindow() {
        guard let paneID = focusedPaneID,
              let currentWindowID = focusedWindowID,
              let currentIndex = windows.firstIndex(where: { $0.id == currentWindowID }),
              windows.count > 1 else { return }
        let nextIndex = (currentIndex + 1) % windows.count
        let targetWindow = windows[nextIndex]
        if targetWindow.id != currentWindowID {
            movePaneToWindow(paneID: paneID, targetWindowID: targetWindow.id)
        }
    }

    /// Moves the focused pane to the previous window.
    func movePaneToPreviousWindow() {
        guard let paneID = focusedPaneID,
              let currentWindowID = focusedWindowID,
              let currentIndex = windows.firstIndex(where: { $0.id == currentWindowID }),
              windows.count > 1 else { return }
        let prevIndex = (currentIndex - 1 + windows.count) % windows.count
        let targetWindow = windows[prevIndex]
        if targetWindow.id != currentWindowID {
            movePaneToWindow(paneID: paneID, targetWindowID: targetWindow.id)
        }
    }

    /// Removes windows that have only empty panes (no worktreeID), unless it's the focused window.
    private func cleanupEmptyWindows() {
        windows.removeAll { window in
            window.id != focusedWindowID
                && window.panes.allSatisfy({ $0.worktreeID == nil })
        }
        if windows.isEmpty {
            focusedWindowID = nil
            focusedPaneID = nil
        }
    }

    func assignWorktree(_ worktreeID: String?, to paneID: UUID) {
        guard let p = pane(for: paneID) else { return }
        p.worktreeID = worktreeID
        saveState()
    }

    func addPane(worktreeID: String? = nil, after paneID: UUID? = nil) {
        guard let window = focusedWindow else { return }
        guard window.panes.count < 5 else { return }
        let newPane = WorktreePane(worktreeID: worktreeID)
        if let afterID = paneID,
           let index = window.panes.firstIndex(where: { $0.id == afterID }) {
            window.panes.insert(newPane, at: index + 1)
        } else {
            window.panes.append(newPane)
        }
        focusedPaneID = newPane.id
        markPendingLabel(newPane.id)
        saveState()
    }

    func splitRight(worktreeID: String? = nil) {
        guard let window = focusedWindow else { return }

        // If worktreeID matches focused pane, create new pane with same worktree
        if let wid = worktreeID, let focused = focusedPane, focused.worktreeID == wid {
            addPane(worktreeID: wid, after: focused.id)
            return
        }

        // If worktreeID already has a pane in this window, focus it
        if let wid = worktreeID, let existingPane = pane(forWorktreeID: wid, in: window) {
            focusedPaneID = existingPane.id
            return
        }

        // Otherwise create new pane after focused pane
        addPane(worktreeID: worktreeID, after: focusedPane?.id)
    }

    /// Opens a worktree in a split. If already visible in the current window, focuses it.
    /// If visible in another window, focuses it. Otherwise creates a new pane.
    func openInSplit(worktreeID: String) {
        guard let window = focusedWindow else { return }

        // If worktree is already visible in this window, focus that pane
        if let existingPane = window.panes.first(where: { $0.worktreeID == worktreeID }) {
            focusedPaneID = existingPane.id
            return
        }

        // If visible in another window, focus it there
        if let loc = findWorktreeLocation(worktreeID) {
            focusedWindowID = loc.windowID
            focusedPaneID = loc.paneID
            return
        }

        // Not visible anywhere — create new pane
        addPane(worktreeID: worktreeID, after: focusedPane?.id)
    }

    func removePane(id: UUID) {
        guard let window = focusedWindow,
              let paneIndex = window.panes.firstIndex(where: { $0.id == id }) else { return }

        let p = window.panes[paneIndex]
        let worktreeID = p.worktreeID

        if window.panes.count == 1 {
            // Last pane in window — remove the entire window
            terminalSessionManager?.terminateSessionsForPane(p.id.uuidString)
            if let worktreeID {
                let othersHaveIt = windows.contains { w in
                    w.id != window.id && w.panes.contains { $0.worktreeID == worktreeID }
                }
                if !othersHaveIt {
                    terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
                }
            }
            removeWindow(id: window.id)
            return
        } else {
            terminalSessionManager?.terminateSessionsForPane(p.id.uuidString)
            window.panes.remove(at: paneIndex)
            if focusedPaneID == id {
                let newIndex = min(max(0, paneIndex - 1), window.panes.count - 1)
                focusedPaneID = window.panes.isEmpty ? nil : window.panes[newIndex].id
            }
            if let worktreeID, !visibleWorktreeIDs.contains(worktreeID) {
                terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
            }
        }
        saveState()
    }

    func closeFocusedPane() {
        guard let id = focusedPaneID else { return }
        removePane(id: id)
    }

    // MARK: - Minimize / Restore

    func minimizePane(id: UUID) {
        guard let p = pane(for: id) else { return }
        p.isMinimized = true
        if focusedPaneID == id {
            focusedPaneID = expandedPanes.first?.id
        }
        saveState()
    }

    func restorePane(id: UUID) {
        guard let p = pane(for: id) else { return }
        p.isMinimized = false
        focusedPaneID = p.id
        saveState()
    }

    func swapMinimized(restorePaneID: UUID) {
        guard let currentFocused = focusedPane else {
            restorePane(id: restorePaneID)
            return
        }
        guard let restoreP = pane(for: restorePaneID), restoreP.isMinimized else { return }
        currentFocused.isMinimized = true
        restoreP.isMinimized = false
        focusedPaneID = restoreP.id
        saveState()
    }

    func focusNextPane() {
        let expanded = expandedPanes
        guard expanded.count > 1,
              let currentID = focusedPaneID,
              let index = expanded.firstIndex(where: { $0.id == currentID }) else { return }
        let nextIndex = (index + 1) % expanded.count
        focusedPaneID = expanded[nextIndex].id
    }

    func focusPreviousPane() {
        let expanded = expandedPanes
        guard expanded.count > 1,
              let currentID = focusedPaneID,
              let index = expanded.firstIndex(where: { $0.id == currentID }) else { return }
        let prevIndex = (index - 1 + expanded.count) % expanded.count
        focusedPaneID = expanded[prevIndex].id
    }

    // MARK: - Move Operations (preserves pane IDs and terminal sessions)

    /// Repositions a pane within the focused window without destroying it.
    func movePane(id: UUID, toIndex: Int) {
        guard let window = focusedWindow,
              let fromIndex = window.panes.firstIndex(where: { $0.id == id }) else { return }
        let p = window.panes.remove(at: fromIndex)
        let clampedIndex = max(0, min(toIndex, window.panes.count))
        window.panes.insert(p, at: clampedIndex)
        saveState()
    }

    func insertPane(worktreeID: String?, at index: Int) {
        guard let window = focusedWindow else { return }
        guard window.panes.count < 5 else { return }
        let newPane = WorktreePane(worktreeID: worktreeID)
        let clampedIndex = max(0, min(index, window.panes.count))
        window.panes.insert(newPane, at: clampedIndex)
        focusedPaneID = newPane.id
        markPendingLabel(newPane.id)
        saveState()
    }

    /// Clears a worktree from all panes that display it (across all windows).
    /// Windows left with no panes are removed entirely.
    func clearWorktree(_ worktreeID: String) {
        for window in windows {
            for pane in window.panes where pane.worktreeID == worktreeID {
                terminalSessionManager?.terminateSessionsForPane(pane.id.uuidString)
            }
            window.panes.removeAll { $0.worktreeID == worktreeID }
        }
        // Remove worktree windows that now have no panes, and diff windows for this worktree
        windows.removeAll { window in
            if case .diff(let path, _) = window.kind, path == worktreeID {
                return true
            }
            return window.panes.isEmpty && {
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
                  !window.panes.contains(where: { $0.id == focusedPaneID }) {
            focusedPaneID = window.panes.first?.id
        } else if focusedWindow == nil {
            // Focused window was removed — pick the first remaining
            focusedWindowID = windows.first?.id
            focusedPaneID = windows.first?.panes.first?.id
        }
        saveState()
    }

    // MARK: - Window Management

    func addWindow() {
        let count = windows.count + 1
        let newPane = WorktreePane()
        let newWindow = WindowState(name: "Window \(count)", panes: [newPane])
        windows.append(newWindow)
        focusWindow(id: newWindow.id)
        markPendingLabel(newPane.id)
        saveState()
    }

    func removeWindow(id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let window = windows[index]
        // Only clean up terminal sessions for worktree windows (diff tabs have no sessions)
        if case .worktrees = window.kind {
            for pane in window.panes {
                terminalSessionManager?.terminateSessionsForPane(pane.id.uuidString)
                if let worktreeID = pane.worktreeID {
                    let othersHaveIt = windows.contains { w in
                        w.id != id && w.panes.contains { $0.worktreeID == worktreeID }
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
                focusedPaneID = windows[newIndex].panes.first?.id
            }
        }
        saveState()
    }

    func focusWindow(id: UUID) {
        guard let window = windows.first(where: { $0.id == id }) else { return }
        focusedWindowID = id
        focusedPaneID = window.panes.first?.id
        saveState()
    }

    func renameWindow(id: UUID, name: String) {
        guard !name.isEmpty, let window = windows.first(where: { $0.id == id }) else { return }
        window.name = name
        saveState()
    }

    // MARK: - Label Prompt

    private func markPendingLabel(_ paneID: UUID) {
        if UserDefaults.standard.bool(forKey: "promptForPaneLabel") {
            pendingLabelPaneID = paneID
        }
    }

    // MARK: - Persistence

    /// Allows views to trigger a save after directly mutating pane properties (e.g. label).
    func saveStateExternally() {
        saveState()
    }

    private struct SavedState: Codable {
        let windows: [WindowSaved]
        let focusedWindowID: String?
        let focusedPaneID: String?

        private enum CodingKeys: String, CodingKey {
            case windows, focusedWindowID, focusedPaneID, focusedColumnID
        }

        init(windows: [WindowSaved], focusedWindowID: String?, focusedPaneID: String?) {
            self.windows = windows
            self.focusedWindowID = focusedWindowID
            self.focusedPaneID = focusedPaneID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            windows = try container.decode([WindowSaved].self, forKey: .windows)
            focusedWindowID = try container.decodeIfPresent(String.self, forKey: .focusedWindowID)
            focusedPaneID = try container.decodeIfPresent(String.self, forKey: .focusedPaneID)
                ?? container.decodeIfPresent(String.self, forKey: .focusedColumnID)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(windows, forKey: .windows)
            try container.encodeIfPresent(focusedWindowID, forKey: .focusedWindowID)
            try container.encodeIfPresent(focusedPaneID, forKey: .focusedPaneID)
        }
    }

    private struct WindowSaved: Codable {
        let id: String
        let name: String
        let panes: [PaneSaved]

        private enum CodingKeys: String, CodingKey {
            case id, name, panes, columns
        }

        init(id: String, name: String, panes: [PaneSaved]) {
            self.id = id
            self.name = name
            self.panes = panes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            panes = try container.decodeIfPresent([PaneSaved].self, forKey: .panes)
                ?? container.decode([PaneSaved].self, forKey: .columns)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(panes, forKey: .panes)
        }
    }

    private struct PaneSaved: Codable {
        let id: String
        let worktreeID: String?
        let showRunnerPanel: Bool
        let isMinimized: Bool?
        let label: String?
        let showLabel: Bool?
        // Legacy field for decoding compat
        let paneCount: Int?

        init(id: String, worktreeID: String?, showRunnerPanel: Bool, isMinimized: Bool = false, label: String? = nil, showLabel: Bool = true) {
            self.id = id
            self.worktreeID = worktreeID
            self.showRunnerPanel = showRunnerPanel
            self.isMinimized = isMinimized
            self.label = label
            self.showLabel = showLabel
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
                    panes: w.panes.map { p in
                        PaneSaved(
                            id: p.id.uuidString,
                            worktreeID: p.worktreeID,
                            showRunnerPanel: p.showRunnerPanel,
                            isMinimized: p.isMinimized,
                            label: p.label,
                            showLabel: p.showLabel
                        )
                    }
                )
            },
            focusedWindowID: focusedWindowID?.uuidString,
            focusedPaneID: focusedPaneID?.uuidString
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
            guard state.windows.first?.panes.isEmpty == false else {
                // Fall through to legacy formats below
                return nil
            }
            let windows = state.windows.map { w in
                WindowState(
                    id: UUID(uuidString: w.id) ?? UUID(),
                    name: w.name,
                    panes: w.panes.map { p in
                        WorktreePane(
                            id: UUID(uuidString: p.id) ?? UUID(),
                            worktreeID: p.worktreeID,
                            showRunnerPanel: p.showRunnerPanel,
                            isMinimized: p.isMinimized ?? false,
                            label: p.label,
                            showLabel: p.showLabel ?? true
                        )
                    }
                )
            }
            let focusedWinID = state.focusedWindowID.flatMap { UUID(uuidString: $0) }
            let focusedPID = state.focusedPaneID.flatMap { UUID(uuidString: $0) }
            return (windows, focusedWinID, focusedPID)
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
                    panes: w.worktreeIDs.map { wtId in
                        WorktreePane(worktreeID: wtId)
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
            let panes = flat.worktreeIDs.map { WorktreePane(worktreeID: $0) }
            let window = WindowState(name: "Window 1", panes: panes)
            return ([window], window.id, window.panes.first?.id)
        }

        return nil
    }
}
