import AppKit
import SwiftUI
import WTCore
import WTTerminal

/// Inner split view for multiple panes within a single worktree column.
/// Does NOT register for worktree drag types to avoid shadowing the outer SplitPaneContainerView.
struct ColumnPanesView: NSViewControllerRepresentable {
    let column: WorktreeColumn
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let findWorktree: (String) -> Worktree?

    private static let minimumPaneWidth: CGFloat = 200

    func makeNSViewController(context: Context) -> EqualSplitViewController {
        let controller = EqualSplitViewController()
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        controller.splitView = splitView

        context.coordinator.column = column
        context.coordinator.paneManager = paneManager
        context.coordinator.terminalSessionManager = terminalSessionManager
        context.coordinator.findWorktree = findWorktree
        context.coordinator.rebuildItems(controller: controller)

        return controller
    }

    func updateNSViewController(_ controller: EqualSplitViewController, context: Context) {
        context.coordinator.column = column
        context.coordinator.paneManager = paneManager
        context.coordinator.terminalSessionManager = terminalSessionManager
        context.coordinator.findWorktree = findWorktree
        context.coordinator.reconcile(controller: controller)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            column: column,
            paneManager: paneManager,
            terminalSessionManager: terminalSessionManager,
            findWorktree: findWorktree
        )
    }

    @MainActor
    class Coordinator {
        var column: WorktreeColumn
        var paneManager: SplitPaneManager
        var terminalSessionManager: TerminalSessionManager
        var findWorktree: (String) -> Worktree?

        private var itemMap: [(paneID: UUID, item: NSSplitViewItem, host: NSHostingController<AnyView>)] = []

        init(
            column: WorktreeColumn,
            paneManager: SplitPaneManager,
            terminalSessionManager: TerminalSessionManager,
            findWorktree: @escaping (String) -> Worktree?
        ) {
            self.column = column
            self.paneManager = paneManager
            self.terminalSessionManager = terminalSessionManager
            self.findWorktree = findWorktree
        }

        func rebuildItems(controller: NSSplitViewController) {
            for entry in itemMap {
                controller.removeSplitViewItem(entry.item)
            }
            itemMap.removeAll()

            for pane in column.panes {
                let host = makeHostingController(for: pane)
                let item = NSSplitViewItem(viewController: host)
                item.minimumThickness = ColumnPanesView.minimumPaneWidth
                item.holdingPriority = .defaultLow
                controller.addSplitViewItem(item)
                itemMap.append((paneID: pane.id, item: item, host: host))
            }

            // Equalize pane widths via controller
            if let eqController = controller as? EqualSplitViewController {
                eqController.equalizeDividers()
            }
        }

        func reconcile(controller: NSSplitViewController) {
            let currentIDs = itemMap.map(\.paneID)
            let newIDs = column.panes.map(\.id)

            if currentIDs == newIDs {
                for (index, pane) in column.panes.enumerated() {
                    itemMap[index].host.rootView = makeView(for: pane)
                }
                return
            }

            // Incremental reconciliation — preserve surviving hosting controllers
            let newIDSet = Set(newIDs)

            // 1. Remove panes that no longer exist
            for i in stride(from: itemMap.count - 1, through: 0, by: -1) {
                if !newIDSet.contains(itemMap[i].paneID) {
                    controller.removeSplitViewItem(itemMap[i].item)
                    itemMap.remove(at: i)
                }
            }

            // 2. Build lookup of surviving items
            var survivingMap: [UUID: (item: NSSplitViewItem, host: NSHostingController<AnyView>)] = [:]
            for entry in itemMap {
                survivingMap[entry.paneID] = (entry.item, entry.host)
            }

            // 3. Remove all surviving items from controller to re-insert in correct order
            for entry in itemMap {
                controller.removeSplitViewItem(entry.item)
            }
            itemMap.removeAll()

            // 4. Rebuild itemMap in new order, reusing surviving items
            for pane in column.panes {
                if let existing = survivingMap[pane.id] {
                    existing.host.rootView = makeView(for: pane)
                    controller.addSplitViewItem(existing.item)
                    itemMap.append((paneID: pane.id, item: existing.item, host: existing.host))
                } else {
                    let host = makeHostingController(for: pane)
                    let item = NSSplitViewItem(viewController: host)
                    item.minimumThickness = ColumnPanesView.minimumPaneWidth
                    item.holdingPriority = .defaultLow
                    controller.addSplitViewItem(item)
                    itemMap.append((paneID: pane.id, item: item, host: host))
                }
            }

            // Equalize pane widths via controller
            if let eqController = controller as? EqualSplitViewController {
                eqController.equalizeDividers()
            }
        }

        private func makeHostingController(for pane: PaneState) -> NSHostingController<AnyView> {
            let view = makeView(for: pane)
            let host = NSHostingController(rootView: view)
            host.sizingOptions = []
            return host
        }

        private func makeView(for pane: PaneState) -> AnyView {
            AnyView(
                PaneContentView(
                    pane: pane,
                    column: column,
                    paneManager: paneManager,
                    terminalSessionManager: terminalSessionManager,
                    findWorktree: findWorktree
                )
            )
        }
    }
}
