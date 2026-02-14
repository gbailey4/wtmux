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

    private static let minimumPaneWidth: CGFloat = 300

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()

        let splitView = DroppableSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        controller.splitView = splitView

        context.coordinator.splitView = splitView
        context.coordinator.paneManager = paneManager
        context.coordinator.rebuildItems(controller: controller, panes: paneManager.panes)

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

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        context.coordinator.findWorktree = findWorktree
        context.coordinator.terminalSessionManager = terminalSessionManager
        context.coordinator.paneManager = paneManager
        context.coordinator.reconcile(controller: controller, panes: paneManager.panes)
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

        func handleDragUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
            guard let splitView else { return .generic }
            let locationInSplitView = splitView.convert(info.draggingLocation, from: nil)

            // Clear all panes first
            for pane in paneManager.panes {
                pane.dropZone = .none
            }

            // Find which pane the cursor is over
            var hitPane = false
            let isSinglePane = paneManager.panes.count == 1
            for entry in itemMap {
                let hostView = entry.host.view
                let paneFrame = hostView.convert(hostView.bounds, to: splitView)
                if paneFrame.contains(locationInSplitView) {
                    hitPane = true
                    if let pane = paneManager.pane(for: entry.paneID) {
                        if isSinglePane {
                            // Single pane: dropping anywhere splits (adds pane to the right)
                            pane.dropZone = .right
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
            var targetPane: PaneState?
            var targetZone: DropZone = .none
            let isSinglePane = paneManager.panes.count == 1

            for entry in itemMap {
                let hostView = entry.host.view
                let paneFrame = hostView.convert(hostView.bounds, to: splitView)
                if paneFrame.contains(locationInSplitView) {
                    targetPane = paneManager.pane(for: entry.paneID)
                    if isSinglePane {
                        targetZone = .right  // Single pane: anywhere = split (add to right)
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

            // Read data synchronously from pasteboard
            let pasteboard = info.draggingPasteboard
            var data = pasteboard.data(forType: WorktreeReference.pasteboardType)
            // Fallback: .draggable() with CodableRepresentation may wrap data differently
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

            // Remove source pane if this is a pane-to-pane move
            if let sourcePaneIDString = ref.sourcePaneID,
               let sourcePaneID = UUID(uuidString: sourcePaneIDString),
               sourcePaneID != targetPane.id {
                paneManager.removePane(id: sourcePaneID)
            }

            switch targetZone {
            case .left:
                if let index = paneManager.panes.firstIndex(where: { $0.id == targetPane.id }) {
                    paneManager.insertPane(worktreeID: ref.worktreeID, at: index)
                }
            case .right:
                paneManager.addPane(worktreeID: ref.worktreeID, after: targetPane.id)
            case .center:
                paneManager.addPane(worktreeID: ref.worktreeID, after: targetPane.id)
            case .none:
                break
            }
            return true
        }

        func handleDragExited() {
            for pane in paneManager.panes {
                pane.dropZone = .none
            }
        }

        // MARK: - Pane Management

        func rebuildItems(controller: NSSplitViewController, panes: [PaneState]) {
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

            // Equalize divider positions (50/50, thirds, etc.) — exclude sidebars by using
            // visible rect after layout; the split view lives in the detail column only.
            DispatchQueue.main.async { [weak splitView] in
                guard let sv = splitView, sv.subviews.count > 1 else { return }
                sv.layoutSubtreeIfNeeded()
                let total: CGFloat
                if sv.isVertical {
                    total = sv.visibleRect.width > 0 ? sv.visibleRect.width : sv.bounds.width
                } else {
                    total = sv.visibleRect.height > 0 ? sv.visibleRect.height : sv.bounds.height
                }
                guard total > 0 else { return }
                let count = sv.subviews.count
                let share = total / CGFloat(count)
                for i in 0..<(count - 1) {
                    let pos = share * CGFloat(i + 1)
                    sv.setPosition(pos, ofDividerAt: i)
                }
            }
        }

        func reconcile(controller: NSSplitViewController, panes: [PaneState]) {
            let currentIDs = itemMap.map(\.paneID)
            let newIDs = panes.map(\.id)

            if currentIDs == newIDs {
                // Same panes, same order — just update rootViews.
                // Re-register after reconcile too: updated SwiftUI content can create new AppKit views
                // that register for drag types and shadow the split view's registration.
                for (index, pane) in panes.enumerated() {
                    itemMap[index].host.rootView = makeView(for: pane)
                }
                splitView?.registerForDraggedTypes([WorktreeReference.pasteboardType])
                return
            }

            // Structural change — rebuild
            rebuildItems(controller: controller, panes: panes)
        }

        private func makeHostingController(for pane: PaneState) -> NSHostingController<AnyView> {
            let view = makeView(for: pane)
            let host = NSHostingController(rootView: view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            return host
        }

        private func makeView(for pane: PaneState) -> AnyView {
            AnyView(
                PaneContentView(
                    pane: pane,
                    paneManager: paneManager,
                    terminalSessionManager: terminalSessionManager,
                    findWorktree: findWorktree
                )
            )
        }
    }
}
