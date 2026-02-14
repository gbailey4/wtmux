import Foundation
import WTTerminal

@MainActor @Observable
final class SplitPaneManager {
    weak var terminalSessionManager: TerminalSessionManager?

    var windows: [WindowState] {
        didSet { saveState() }
    }
    var focusedWindowID: UUID?
    var focusedPaneID: UUID?

    var focusedWindow: WindowState? {
        guard let id = focusedWindowID else { return windows.first }
        return windows.first { $0.id == id } ?? windows.first
    }

    var panes: [PaneState] {
        focusedWindow?.panes ?? []
    }

    var focusedPane: PaneState? {
        guard let win = focusedWindow else { return nil }
        guard let id = focusedPaneID else { return win.panes.first }
        return win.panes.first { $0.id == id } ?? win.panes.first
    }

    /// All worktree IDs currently visible in any pane across all windows.
    var visibleWorktreeIDs: Set<String> {
        Set(windows.flatMap { $0.panes.compactMap(\.worktreeID) })
    }

    private static let stateKey = "splitPaneState"

    init() {
        if let (restoredWindows, focusedWinID, focusedPaneID) = Self.loadState() {
            self.windows = restoredWindows
            self.focusedWindowID = focusedWinID ?? restoredWindows.first?.id
            self.focusedPaneID = focusedPaneID ?? restoredWindows.first?.panes.first?.id
        } else {
            let initial = WindowState(name: "Window 1", panes: [PaneState()])
            self.windows = [initial]
            self.focusedWindowID = initial.id
            self.focusedPaneID = initial.panes.first?.id
        }
    }

    func pane(for id: UUID) -> PaneState? {
        for window in windows {
            if let pane = window.panes.first(where: { $0.id == id }) {
                return pane
            }
        }
        return nil
    }

    /// Focuses the first pane (across all windows) that displays the given worktree.
    func focusPane(containing worktreeID: String) {
        for window in windows {
            if let pane = window.panes.first(where: { $0.worktreeID == worktreeID }) {
                focusedWindowID = window.id
                focusedPaneID = pane.id
                return
            }
        }
    }

    func assignWorktree(_ worktreeID: String?, to paneID: UUID) {
        guard let pane = pane(for: paneID) else { return }
        pane.worktreeID = worktreeID
        saveState()
    }

    func addPane(worktreeID: String? = nil, after paneID: UUID? = nil) {
        guard let window = focusedWindow else { return }
        guard window.panes.count < 5 else { return }
        let newPane = PaneState(worktreeID: worktreeID)
        if let afterID = paneID, let index = window.panes.firstIndex(where: { $0.id == afterID }) {
            window.panes.insert(newPane, at: index + 1)
        } else {
            window.panes.append(newPane)
        }
        focusedPaneID = newPane.id
        saveState()
    }

    func splitRight(worktreeID: String? = nil) {
        addPane(worktreeID: worktreeID, after: focusedPaneID)
    }

    func removePane(id: UUID) {
        guard let window = focusedWindow else { return }
        guard let index = window.panes.firstIndex(where: { $0.id == id }) else { return }
        let removedWorktreeID = window.panes[index].worktreeID

        if window.panes.count == 1 {
            // Closing the final pane: clear it instead of removing (keep at least one pane).
            window.panes[index].worktreeID = nil
            if let worktreeID = removedWorktreeID {
                terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
            }
        } else {
            window.panes.remove(at: index)
            if focusedPaneID == id {
                let newIndex = max(0, index - 1)
                focusedPaneID = window.panes[newIndex].id
            }
            if let worktreeID = removedWorktreeID, !visibleWorktreeIDs.contains(worktreeID) {
                terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
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
        guard let currentID = focusedPaneID,
              let index = window.panes.firstIndex(where: { $0.id == currentID }) else { return }
        let nextIndex = (index + 1) % window.panes.count
        focusedPaneID = window.panes[nextIndex].id
    }

    func focusPreviousPane() {
        guard let window = focusedWindow else { return }
        guard let currentID = focusedPaneID,
              let index = window.panes.firstIndex(where: { $0.id == currentID }) else { return }
        let prevIndex = (index - 1 + window.panes.count) % window.panes.count
        focusedPaneID = window.panes[prevIndex].id
    }

    func movePane(fromIndex: Int, toIndex: Int) {
        guard let window = focusedWindow else { return }
        guard fromIndex != toIndex,
              window.panes.indices.contains(fromIndex),
              window.panes.indices.contains(toIndex) else { return }
        let pane = window.panes.remove(at: fromIndex)
        window.panes.insert(pane, at: toIndex)
        saveState()
    }

    func insertPane(worktreeID: String?, at index: Int) {
        guard let window = focusedWindow else { return }
        guard window.panes.count < 5 else { return }
        let newPane = PaneState(worktreeID: worktreeID)
        let clampedIndex = max(0, min(index, window.panes.count))
        window.panes.insert(newPane, at: clampedIndex)
        focusedPaneID = newPane.id
        saveState()
    }

    /// Clears a worktree from all panes that display it (across all windows).
    func clearWorktree(_ worktreeID: String) {
        for window in windows {
            for pane in window.panes where pane.worktreeID == worktreeID {
                pane.worktreeID = nil
            }
            let nonEmpty = window.panes.filter { $0.worktreeID != nil }
            if !nonEmpty.isEmpty && window.panes.count > 1 {
                window.panes.removeAll { $0.worktreeID == nil }
            }
        }
        terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
        saveState()
    }

    // MARK: - Window Management

    func addWindow() {
        let count = windows.count + 1
        let newWindow = WindowState(name: "Window \(count)", panes: [PaneState()])
        windows.append(newWindow)
        focusWindow(id: newWindow.id)
        saveState()
    }

    func removeWindow(id: UUID) {
        guard windows.count > 1 else { return }
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let window = windows[index]
        for pane in window.panes {
            if let worktreeID = pane.worktreeID {
                let othersHaveIt = windows.contains { w in
                    w.id != id && w.panes.contains { $0.worktreeID == worktreeID }
                }
                if !othersHaveIt {
                    terminalSessionManager?.terminateAllSessionsForWorktree(worktreeID)
                }
            }
        }
        windows.remove(at: index)
        if focusedWindowID == id {
            let newIndex = max(0, index - 1)
            focusedWindowID = windows[newIndex].id
            focusedPaneID = windows[newIndex].panes.first?.id
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

    // MARK: - Persistence

    private struct SavedState: Codable {
        let windows: [WindowSaved]
        let focusedWindowID: String?
        let focusedPaneID: String?
    }

    private struct WindowSaved: Codable {
        let id: String
        let name: String
        let worktreeIDs: [String?]
    }

    private func saveState() {
        let state = SavedState(
            windows: windows.map { w in
                WindowSaved(
                    id: w.id.uuidString,
                    name: w.name,
                    worktreeIDs: w.panes.map(\.worktreeID)
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
        if let state = try? JSONDecoder().decode(SavedState.self, from: data), !state.windows.isEmpty {
            let windows = state.windows.map { w in
                WindowState(
                    id: UUID(uuidString: w.id) ?? UUID(),
                    name: w.name,
                    panes: w.worktreeIDs.map { PaneState(worktreeID: $0) }
                )
            }
            let focusedWinID = state.focusedWindowID.flatMap { UUID(uuidString: $0) }
            let focusedPaneID = state.focusedPaneID.flatMap { UUID(uuidString: $0) }
            return (windows, focusedWinID, focusedPaneID)
        }
        // Migrate from old flat format
        struct LegacySavedState: Codable {
            let worktreeIDs: [String?]
        }
        if let legacy = try? JSONDecoder().decode(LegacySavedState.self, from: data), !legacy.worktreeIDs.isEmpty {
            let panes = legacy.worktreeIDs.map { PaneState(worktreeID: $0) }
            let window = WindowState(name: "Window 1", panes: panes)
            return ([window], window.id, panes.first?.id)
        }
        return nil
    }
}
