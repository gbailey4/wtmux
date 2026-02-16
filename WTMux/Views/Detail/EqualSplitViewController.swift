import AppKit

/// NSSplitViewController subclass that distributes space equally among all subviews.
/// Uses `viewDidLayout()` to set divider positions — called after layout completes
/// so bounds are always valid. No deferred passes or stored proportions needed.
class EqualSplitViewController: NSSplitViewController {

    /// Guard flag to prevent re-entrant calls when setPosition triggers layout.
    private var isApplying = false

    /// Called after adding/removing split view items to re-equalize.
    func equalizeDividers() {
        applyEqualPositions()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyEqualPositions()
    }

    // MARK: - Private

    private func applyEqualPositions() {
        let count = splitViewItems.count
        guard count > 1, !isApplying else { return }

        let isVertical = splitView.isVertical
        let totalSize = isVertical ? splitView.bounds.width : splitView.bounds.height
        let dividerTotal = splitView.dividerThickness * CGFloat(count - 1)
        let available = totalSize - dividerTotal
        let itemSize = available / CGFloat(count)
        guard itemSize > 0 else { return }

        isApplying = true
        for i in 0..<(count - 1) {
            let position = itemSize * CGFloat(i + 1) + splitView.dividerThickness * CGFloat(i)
            splitView.setPosition(position, ofDividerAt: i)
        }
        isApplying = false
    }
}
