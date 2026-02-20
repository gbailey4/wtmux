import AppKit
import Foundation
import os.log
import SwiftUI
import WTCore
import WTTerminal

private let dragLogger = Logger(subsystem: "com.wtmux", category: "SplitPaneDrag")

// MARK: - DroppableSplitView

/// NSSplitView subclass that handles drag-and-drop at the AppKit level,
/// bypassing the unreliable SwiftUI .onDrop across NSViewControllerRepresentable boundaries.
class DroppableSplitView: NSSplitView {
    var handleDrag: ((_ info: NSDraggingInfo) -> NSDragOperation)?
    var handleDrop: ((_ info: NSDraggingInfo) -> Bool)?
    var handleExit: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([WorktreeReference.pasteboardType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "nil"
        dragLogger.info("draggingEntered pasteboardTypes=\(types)")
        return handleDrag?(sender) ?? .generic
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return handleDrag?(sender) ?? .generic
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        handleExit?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragLogger.info("prepareForDragOperation")
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let result = handleDrop?(sender) ?? false
        dragLogger.info("performDragOperation result=\(result)")
        return result
    }
}

// MARK: - SplitPaneContainerView

struct SplitPaneContainerView: NSViewControllerRepresentable {
    let paneManager: SplitPaneManager
    let terminalSessionManager: TerminalSessionManager
    let findWorktree: (String) -> Worktree?
    var isSharedLayout: Bool = false

    private static let minimumPaneWidth: CGFloat = 300

    func makeNSViewController(context: Context) -> EqualSplitViewController {
        let controller = EqualSplitViewController()

        let splitView = DroppableSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        controller.splitView = splitView

        context.coordinator.splitView = splitView
        context.coordinator.paneManager = paneManager
        context.coordinator.rebuildItems(controller: controller, panes: paneManager.expandedPanes)

        splitView.handleDrag = { [weak coordinator = context.coordinator] info in
            coordinator?.handleDragUpdated(info) ?? .generic
        }
        splitView.handleDrop = { [weak coordinator = context.coordinator] info in
            coordinator?.handlePerformDrag(info) ?? false
        }
        splitView.handleExit = { [weak coordinator = context.coordinator] in
            coordinator?.handleDragExited()
        }

        return controller
    }

    func updateNSViewController(_ controller: EqualSplitViewController, context: Context) {
        context.coordinator.findWorktree = findWorktree
        context.coordinator.terminalSessionManager = terminalSessionManager
        context.coordinator.paneManager = paneManager
        context.coordinator.isSharedLayout = isSharedLayout
        context.coordinator.reconcile(controller: controller, panes: paneManager.expandedPanes)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            paneManager: paneManager,
            terminalSessionManager: terminalSessionManager,
            findWorktree: findWorktree
        )
    }

    @MainActor
    class Coordinator: NSObject {
        var paneManager: SplitPaneManager
        var terminalSessionManager: TerminalSessionManager
        var findWorktree: (String) -> Worktree?
        var isSharedLayout: Bool = false
        weak var splitView: DroppableSplitView?

        // Stable mapping: paneID → (splitViewItem, hostingController)
        private var itemMap: [(paneID: UUID, item: NSSplitViewItem, host: NSHostingController<AnyView>)] = []

        init(
            paneManager: SplitPaneManager,
            terminalSessionManager: TerminalSessionManager,
            findWorktree: @escaping (String) -> Worktree?
        ) {
            self.paneManager = paneManager
            self.terminalSessionManager = terminalSessionManager
            self.findWorktree = findWorktree
        }

        // MARK: - Drag & Drop

        private func paneHasActiveSessions(_ pane: WorktreePane) -> Bool {
            terminalSessionManager.terminalSession(forPane: pane.id.uuidString) != nil
        }

        func handleDragUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
            guard let splitView else { return .generic }
            let locationInSplitView = splitView.convert(info.draggingLocation, from: nil)

            // Clear all panes first
            for pane in paneManager.panes {
                pane.dropZone = .none
            }

            // Find which pane the cursor is over
            var hitPane = false
            let isSinglePane = paneManager.expandedPanes.count == 1
            for entry in itemMap {
                let hostView = entry.host.view
                let paneFrame = hostView.convert(hostView.bounds, to: splitView)
                if paneFrame.contains(locationInSplitView) {
                    hitPane = true
                    if let pane = paneManager.pane(for: entry.paneID) {
                        if isSinglePane {
                            if paneHasActiveSessions(pane) {
                                pane.dropZone = .right
                            } else {
                                pane.dropZone = .center
                            }
                        } else {
                            let localPoint = hostView.convert(locationInSplitView, from: splitView)
                            let size = hostView.bounds.size
                            let z = DropIndicatorView.zone(
                                for: CGPoint(x: localPoint.x, y: localPoint.y),
                                in: size
                            )
                            pane.dropZone = (z == .center) ? .right : z  // center shows as right-edge indicator
                        }
                    }
                    break
                }
            }
            if !hitPane {
                dragLogger.info("handleDragUpdated no hit loc=\(locationInSplitView.debugDescription) paneCount=\(self.itemMap.count)")
            }

            return .copy
        }

        func handlePerformDrag(_ info: NSDraggingInfo) -> Bool {
            guard let splitView else { return false }
            let locationInSplitView = splitView.convert(info.draggingLocation, from: nil)

            // Find target pane and its drop zone
            var targetPane: WorktreePane?
            var targetZone: DropZone = .none
            let isSinglePane = paneManager.expandedPanes.count == 1

            for entry in itemMap {
                let hostView = entry.host.view
                let paneFrame = hostView.convert(hostView.bounds, to: splitView)
                if paneFrame.contains(locationInSplitView) {
                    targetPane = paneManager.pane(for: entry.paneID)
                    if isSinglePane {
                        if paneHasActiveSessions(targetPane!) {
                            targetZone = .right
                        } else {
                            targetZone = .center
                        }
                    } else {
                        let localPoint = hostView.convert(locationInSplitView, from: splitView)
                        let size = hostView.bounds.size
                        let z = DropIndicatorView.zone(
                            for: CGPoint(x: localPoint.x, y: localPoint.y),
                            in: size
                        )
                        targetZone = (z == .center) ? .right : z  // center = split right
                    }
                    break
                }
            }

            // Clear all drop indicators
            for pane in paneManager.panes {
                pane.dropZone = .none
            }

            guard let targetPane else {
                dragLogger.info("handlePerformDrag no target pane loc=\(locationInSplitView.debugDescription)")
                return false
            }

            let pasteboard = info.draggingPasteboard

            // --- Worktree drag (from sidebar or pane header) ---
            var data = pasteboard.data(forType: WorktreeReference.pasteboardType)
            if data == nil, let item = pasteboard.pasteboardItems?.first {
                data = item.data(forType: WorktreeReference.pasteboardType)
            }
            if data == nil {
                let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "nil"
                dragLogger.info("handlePerformDrag pasteboard nil types=\(types)")
            }
            guard let data,
                  let ref = try? JSONDecoder().decode(WorktreeReference.self, from: data) else {
                dragLogger.info("handlePerformDrag decode failed")
                return false
            }
            dragLogger.info("Drag: drop succeeded worktreeID=\(ref.worktreeID) zone=\(String(describing: targetZone))")

            let sourcePaneUUID = ref.sourcePaneID.flatMap { UUID(uuidString: $0) }

            // --- Sidebar drag (no sourcePaneID) ---
            if sourcePaneUUID == nil {
                // Single-instance guard: focus existing instead of duplicating
                if targetPane.worktreeID != ref.worktreeID,
                   let loc = paneManager.findWorktreeLocation(ref.worktreeID) {
                    paneManager.focusedWindowID = loc.windowID
                    paneManager.focusedPaneID = loc.paneID
                    return true
                }

                // Same-worktree drop from sidebar: create new pane with same worktree
                if targetPane.worktreeID == ref.worktreeID {
                    paneManager.focusedPaneID = targetPane.id
                    paneManager.addPane(worktreeID: ref.worktreeID, after: targetPane.id)
                    return true
                }

                // New pane from sidebar
                switch targetZone {
                case .left:
                    if let index = paneManager.panes.firstIndex(where: { $0.id == targetPane.id }) {
                        paneManager.insertPane(worktreeID: ref.worktreeID, at: index)
                    }
                case .right:
                    paneManager.addPane(worktreeID: ref.worktreeID, after: targetPane.id)
                case .center:
                    paneManager.assignWorktree(ref.worktreeID, to: targetPane.id)
                case .none:
                    break
                }
                return true
            }

            // --- Pane drag (sourcePaneID is the pane ID) ---
            let sourcePaneID = sourcePaneUUID!
            let sourcePane = paneManager.pane(for: sourcePaneID)

            // Same-worktree drop: just focus the target
            if targetPane.worktreeID == ref.worktreeID {
                paneManager.focusedPaneID = targetPane.id
                return true
            }

            // Different worktree, left/right zone: reorder by moving
            if targetZone == .left || targetZone == .right {
                guard let sourcePane else { return false }
                let targetIndex: Int = {
                    guard let ti = paneManager.panes.firstIndex(where: { $0.id == targetPane.id }) else { return 0 }
                    return targetZone == .left ? ti : ti + 1
                }()

                // Reposition the whole pane
                paneManager.movePane(id: sourcePane.id, toIndex: targetIndex)
                return true
            }

            // Center zone: replace target pane's worktree assignment
            if targetZone == .center {
                // Remove source pane (terminates sessions)
                paneManager.removePane(id: sourcePaneID)
                paneManager.assignWorktree(ref.worktreeID, to: targetPane.id)
                return true
            }

            return true
        }

        func handleDragExited() {
            for pane in paneManager.panes {
                pane.dropZone = .none
            }
        }

        // MARK: - Pane Management

        func rebuildItems(controller: NSSplitViewController, panes: [WorktreePane]) {
            for entry in itemMap {
                controller.removeSplitViewItem(entry.item)
            }
            itemMap.removeAll()

            for pane in panes {
                let host = makeHostingController(for: pane)
                let item = NSSplitViewItem(viewController: host)
                item.minimumThickness = SplitPaneContainerView.minimumPaneWidth
                item.holdingPriority = .defaultLow
                controller.addSplitViewItem(item)
                itemMap.append((paneID: pane.id, item: item, host: host))
            }

            // Re-register after rebuild so new hosting views don't shadow our type
            splitView?.registerForDraggedTypes([WorktreeReference.pasteboardType])
            dragLogger.info("rebuildItems paneCount=\(panes.count)")

            // Equalize divider positions via controller
            if let eqController = controller as? EqualSplitViewController {
                eqController.equalizeDividers()
            }
        }

        func reconcile(controller: NSSplitViewController, panes: [WorktreePane]) {
            let currentIDs = itemMap.map(\.paneID)
            let newIDs = panes.map(\.id)

            if currentIDs == newIDs {
                // Same panes, same order — just update rootViews.
                for (index, pane) in panes.enumerated() {
                    itemMap[index].host.rootView = makeView(for: pane)
                }
                splitView?.registerForDraggedTypes([WorktreeReference.pasteboardType])
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
            for pane in panes {
                if let existing = survivingMap[pane.id] {
                    existing.host.rootView = makeView(for: pane)
                    controller.addSplitViewItem(existing.item)
                    itemMap.append((paneID: pane.id, item: existing.item, host: existing.host))
                } else {
                    let host = makeHostingController(for: pane)
                    let item = NSSplitViewItem(viewController: host)
                    item.minimumThickness = SplitPaneContainerView.minimumPaneWidth
                    item.holdingPriority = .defaultLow
                    controller.addSplitViewItem(item)
                    itemMap.append((paneID: pane.id, item: item, host: host))
                }
            }

            splitView?.registerForDraggedTypes([WorktreeReference.pasteboardType])
            dragLogger.info("reconcile incremental paneCount=\(panes.count)")

            // Equalize divider positions via controller
            if let eqController = controller as? EqualSplitViewController {
                eqController.equalizeDividers()
            }
        }

        private func makeHostingController(for pane: WorktreePane) -> NSHostingController<AnyView> {
            let view = makeView(for: pane)
            let host = NSHostingController(rootView: view)
            host.sizingOptions = []
            return host
        }

        private func makeView(for pane: WorktreePane) -> AnyView {
            AnyView(
                WorktreePaneView(
                    pane: pane,
                    paneManager: paneManager,
                    terminalSessionManager: terminalSessionManager,
                    findWorktree: findWorktree,
                    isSharedLayout: isSharedLayout
                )
            )
        }
    }
}
