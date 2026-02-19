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

    private static let minimumColumnWidth: CGFloat = 300

    func makeNSViewController(context: Context) -> EqualSplitViewController {
        let controller = EqualSplitViewController()

        let splitView = DroppableSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        controller.splitView = splitView

        context.coordinator.splitView = splitView
        context.coordinator.paneManager = paneManager
        context.coordinator.rebuildItems(controller: controller, columns: paneManager.expandedColumns)

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
        context.coordinator.reconcile(controller: controller, columns: paneManager.expandedColumns)
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

        // Stable mapping: columnID → (splitViewItem, hostingController)
        private var itemMap: [(columnID: UUID, item: NSSplitViewItem, host: NSHostingController<AnyView>)] = []

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

        private func columnHasActiveSessions(_ column: WorktreeColumn) -> Bool {
            terminalSessionManager.terminalSession(forColumn: column.id.uuidString) != nil
        }

        func handleDragUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
            guard let splitView else { return .generic }
            let locationInSplitView = splitView.convert(info.draggingLocation, from: nil)

            // Clear all columns first
            for column in paneManager.columns {
                column.dropZone = .none
            }

            // Find which column the cursor is over
            var hitColumn = false
            let isSingleColumn = paneManager.expandedColumns.count == 1
            for entry in itemMap {
                let hostView = entry.host.view
                let columnFrame = hostView.convert(hostView.bounds, to: splitView)
                if columnFrame.contains(locationInSplitView) {
                    hitColumn = true
                    if let column = paneManager.column(for: entry.columnID) {
                        if isSingleColumn {
                            if columnHasActiveSessions(column) {
                                column.dropZone = .right
                            } else {
                                column.dropZone = .center
                            }
                        } else {
                            let localPoint = hostView.convert(locationInSplitView, from: splitView)
                            let size = hostView.bounds.size
                            let z = DropIndicatorView.zone(
                                for: CGPoint(x: localPoint.x, y: localPoint.y),
                                in: size
                            )
                            column.dropZone = (z == .center) ? .right : z  // center shows as right-edge indicator
                        }
                    }
                    break
                }
            }
            if !hitColumn {
                dragLogger.info("handleDragUpdated no hit loc=\(locationInSplitView.debugDescription) columnCount=\(self.itemMap.count)")
            }

            return .copy
        }

        func handlePerformDrag(_ info: NSDraggingInfo) -> Bool {
            guard let splitView else { return false }
            let locationInSplitView = splitView.convert(info.draggingLocation, from: nil)

            // Find target column and its drop zone
            var targetColumn: WorktreeColumn?
            var targetZone: DropZone = .none
            let isSingleColumn = paneManager.expandedColumns.count == 1

            for entry in itemMap {
                let hostView = entry.host.view
                let columnFrame = hostView.convert(hostView.bounds, to: splitView)
                if columnFrame.contains(locationInSplitView) {
                    targetColumn = paneManager.column(for: entry.columnID)
                    if isSingleColumn {
                        if columnHasActiveSessions(targetColumn!) {
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
            for column in paneManager.columns {
                column.dropZone = .none
            }

            guard let targetColumn else {
                dragLogger.info("handlePerformDrag no target column loc=\(locationInSplitView.debugDescription)")
                return false
            }

            let pasteboard = info.draggingPasteboard

            // --- Worktree drag (from sidebar or column header) ---
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

            let sourceColumnUUID = ref.sourcePaneID.flatMap { UUID(uuidString: $0) }

            // --- Sidebar drag (no sourcePaneID) ---
            if sourceColumnUUID == nil {
                // Single-instance guard: focus existing instead of duplicating
                if targetColumn.worktreeID != ref.worktreeID,
                   let loc = paneManager.findWorktreeLocation(ref.worktreeID) {
                    paneManager.focusedWindowID = loc.windowID
                    paneManager.focusedColumnID = loc.columnID
                    return true
                }

                // Same-worktree drop from sidebar: create new column with same worktree
                if targetColumn.worktreeID == ref.worktreeID {
                    paneManager.focusedColumnID = targetColumn.id
                    paneManager.addColumn(worktreeID: ref.worktreeID, after: targetColumn.id)
                    return true
                }

                // New column from sidebar
                switch targetZone {
                case .left:
                    if let index = paneManager.columns.firstIndex(where: { $0.id == targetColumn.id }) {
                        paneManager.insertColumn(worktreeID: ref.worktreeID, at: index)
                    }
                case .right:
                    paneManager.addColumn(worktreeID: ref.worktreeID, after: targetColumn.id)
                case .center:
                    paneManager.assignWorktree(ref.worktreeID, to: targetColumn.id)
                case .none:
                    break
                }
                return true
            }

            // --- Column drag (sourcePaneID is actually the column ID now) ---
            let sourceColumnID = sourceColumnUUID!
            let sourceColumn = paneManager.column(for: sourceColumnID)

            // Same-worktree drop: just focus the target
            if targetColumn.worktreeID == ref.worktreeID {
                paneManager.focusedColumnID = targetColumn.id
                return true
            }

            // Different worktree, left/right zone: reorder by moving
            if targetZone == .left || targetZone == .right {
                guard let sourceColumn else { return false }
                let targetIndex: Int = {
                    guard let ti = paneManager.columns.firstIndex(where: { $0.id == targetColumn.id }) else { return 0 }
                    return targetZone == .left ? ti : ti + 1
                }()

                // Reposition the whole column
                paneManager.moveColumn(id: sourceColumn.id, toIndex: targetIndex)
                return true
            }

            // Center zone: replace target column's worktree assignment
            if targetZone == .center {
                // Remove source column (terminates sessions)
                paneManager.removeColumn(id: sourceColumnID)
                paneManager.assignWorktree(ref.worktreeID, to: targetColumn.id)
                return true
            }

            return true
        }

        func handleDragExited() {
            for column in paneManager.columns {
                column.dropZone = .none
            }
        }

        // MARK: - Column Management

        func rebuildItems(controller: NSSplitViewController, columns: [WorktreeColumn]) {
            for entry in itemMap {
                controller.removeSplitViewItem(entry.item)
            }
            itemMap.removeAll()

            for column in columns {
                let host = makeHostingController(for: column)
                let item = NSSplitViewItem(viewController: host)
                item.minimumThickness = SplitPaneContainerView.minimumColumnWidth
                item.holdingPriority = .defaultLow
                controller.addSplitViewItem(item)
                itemMap.append((columnID: column.id, item: item, host: host))
            }

            // Re-register after rebuild so new hosting views don't shadow our type
            splitView?.registerForDraggedTypes([WorktreeReference.pasteboardType])
            dragLogger.info("rebuildItems columnCount=\(columns.count)")

            // Equalize divider positions via controller
            if let eqController = controller as? EqualSplitViewController {
                eqController.equalizeDividers()
            }
        }

        func reconcile(controller: NSSplitViewController, columns: [WorktreeColumn]) {
            let currentIDs = itemMap.map(\.columnID)
            let newIDs = columns.map(\.id)

            if currentIDs == newIDs {
                // Same columns, same order — just update rootViews.
                for (index, column) in columns.enumerated() {
                    itemMap[index].host.rootView = makeView(for: column)
                }
                splitView?.registerForDraggedTypes([WorktreeReference.pasteboardType])
                return
            }

            // Incremental reconciliation — preserve surviving hosting controllers
            let newIDSet = Set(newIDs)

            // 1. Remove columns that no longer exist
            for i in stride(from: itemMap.count - 1, through: 0, by: -1) {
                if !newIDSet.contains(itemMap[i].columnID) {
                    controller.removeSplitViewItem(itemMap[i].item)
                    itemMap.remove(at: i)
                }
            }

            // 2. Build lookup of surviving items
            var survivingMap: [UUID: (item: NSSplitViewItem, host: NSHostingController<AnyView>)] = [:]
            for entry in itemMap {
                survivingMap[entry.columnID] = (entry.item, entry.host)
            }

            // 3. Remove all surviving items from controller to re-insert in correct order
            for entry in itemMap {
                controller.removeSplitViewItem(entry.item)
            }
            itemMap.removeAll()

            // 4. Rebuild itemMap in new order, reusing surviving items
            for column in columns {
                if let existing = survivingMap[column.id] {
                    existing.host.rootView = makeView(for: column)
                    controller.addSplitViewItem(existing.item)
                    itemMap.append((columnID: column.id, item: existing.item, host: existing.host))
                } else {
                    let host = makeHostingController(for: column)
                    let item = NSSplitViewItem(viewController: host)
                    item.minimumThickness = SplitPaneContainerView.minimumColumnWidth
                    item.holdingPriority = .defaultLow
                    controller.addSplitViewItem(item)
                    itemMap.append((columnID: column.id, item: item, host: host))
                }
            }

            splitView?.registerForDraggedTypes([WorktreeReference.pasteboardType])
            dragLogger.info("reconcile incremental columnCount=\(columns.count)")

            // Equalize divider positions via controller
            if let eqController = controller as? EqualSplitViewController {
                eqController.equalizeDividers()
            }
        }

        private func makeHostingController(for column: WorktreeColumn) -> NSHostingController<AnyView> {
            let view = makeView(for: column)
            let host = NSHostingController(rootView: view)
            host.sizingOptions = []
            return host
        }

        private func makeView(for column: WorktreeColumn) -> AnyView {
            AnyView(
                WorktreeColumnView(
                    column: column,
                    paneManager: paneManager,
                    terminalSessionManager: terminalSessionManager,
                    findWorktree: findWorktree,
                    isSharedLayout: isSharedLayout
                )
            )
        }
    }
}
