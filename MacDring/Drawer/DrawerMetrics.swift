import CoreGraphics

/// Deterministic drawer sizing. Computing the drawer's size from the item count
/// and appearance settings (rather than relying on SwiftUI's `fittingSize`, which
/// is ambiguous for a `ScrollView`/`LazyVGrid`) keeps the panel a sensible size
/// and lets `EdgeLayout` position it precisely. Pure and unit-testable.
enum DrawerMetrics {

    static let padding: CGFloat = 28        // 14 on each side
    static let headerHeight: CGFloat = 30
    static let gridSpacing: CGFloat = 12
    static let gridInterColumn: CGFloat = 10
    /// Extra height reserved for the filter field (plus its stack gap) when a drawer
    /// is searchable, so the grid still fits without a scroll bar. See `contentSize`.
    static let searchBarHeight: CGFloat = 40

    /// Height of one Finder-style list row (its small icon plus padding). The list
    /// keeps the drawer's configured size and scrolls, fitting more of these compact
    /// rows than the grid's cells.
    static let listRowHeight: CGFloat = 24
    /// Floor width for the list layout, so a one-column tab still shows the name and a
    /// date. Above it, the configured columns drive the width (and which metadata
    /// columns fit — see `ItemView`).
    static let listMinWidth: CGFloat = 220

    /// Size for a notes drawer, derived from the tab's grid dimensions (so the
    /// Columns/Rows steppers also size the text area), clamped to the screen.
    static func notesSize(columns: Int, rows: Int, iconSize: CGFloat, in visibleFrame: CGRect) -> CGSize {
        let columns = PersistedLayoutBounds.clampedGridColumns(columns)
        let rows = PersistedLayoutBounds.clampedGridRows(rows)
        let width = padding + CGFloat(columns) * (iconSize + 28)
        let height = padding + headerHeight + CGFloat(rows) * (iconSize + 26)
        return CGSize(width: min(max(width, 260), visibleFrame.width - 16),
                      height: min(max(height, 180), visibleFrame.height - 16))
    }

    /// The list layout's width for `columns` configured columns at `iconSize`: the
    /// configured columns drive it (same footprint as the grid), floored so a
    /// one-column tab still shows a name + date. Shared by `contentSize` and the row
    /// view so the rendered columns match the drawer's actual width.
    static func listWidth(columns: Int, iconSize: CGFloat) -> CGFloat {
        let cols = PersistedLayoutBounds.clampedGridColumns(columns)
        let gridWidth = padding + CGFloat(cols) * (iconSize + 28) + CGFloat(cols - 1) * gridInterColumn
        return max(gridWidth, listMinWidth)
    }

    /// Which metadata columns a list row can fit at `width`: the **date** always, the
    /// **size** once there's room, the **kind** once there's more — so a narrow drawer
    /// shows fewer columns instead of overflowing them. Pure, so it's unit-tested.
    static func listMetaColumns(forWidth width: CGFloat) -> (size: Bool, kind: Bool) {
        (size: width >= 280, kind: width >= 360)
    }

    /// Number of grid rows to show: the tab's configured row count (its height),
    /// grown if needed so items/slots placed beyond it stay visible. The empty
    /// cells within are the droppable gaps for free arrangement.
    static func gridRowCount(configuredRows: Int, maxSlot: Int, itemCount: Int, columns: Int) -> Int {
        let cols = PersistedLayoutBounds.clampedGridColumns(columns)
        let configuredRows = PersistedLayoutBounds.clampedGridRows(configuredRows)
        let maxSlot = PersistedLayoutBounds.normalizedSlot(maxSlot)
        let itemCount = min(max(itemCount, 0), PersistedLayoutBounds.maximumSlotCount)
        let slotRows = maxSlot >= 0 ? (maxSlot / cols) + 1 : 0
        let itemRows = itemCount > 0 ? ((itemCount - 1) / cols) + 1 : 0
        return max(configuredRows, slotRows, itemRows, 1)
    }

    /// Number of valid row-major destination cells to render. The final row may be
    /// partial so it ends exactly at the maximum slot rather than exposing larger ids.
    static func renderedGridSlotCount(rows: Int, columns: Int) -> Int {
        let cols = PersistedLayoutBounds.clampedGridColumns(columns)
        let maxRows = (PersistedLayoutBounds.maximumSlotCount + cols - 1) / cols
        let rows = min(max(rows, 0), maxRows)
        return min(rows * cols, PersistedLayoutBounds.maximumSlotCount)
    }

    /// The content size for a drawer, clamped to fit on `visibleFrame`. For the
    /// grid, height is driven by the (configured, possibly grown) row count.
    static func contentSize(itemCount: Int,
                            maxSlot: Int,
                            configuredRows: Int,
                            layout: DrawerLayout,
                            iconSize: CGFloat,
                            columns: Int,
                            searchable: Bool = false,
                            in visibleFrame: CGRect) -> CGSize {
        let configuredRows = PersistedLayoutBounds.clampedGridRows(configuredRows)
        let columns = PersistedLayoutBounds.clampedGridColumns(columns)
        var size: CGSize
        switch layout {
        case .grid:
            let cols = columns
            let rows = gridRowCount(configuredRows: configuredRows, maxSlot: maxSlot, itemCount: itemCount, columns: cols)
            let cellWidth = iconSize + 28
            let cellHeight = iconSize + 26
            let width = padding + CGFloat(cols) * cellWidth + CGFloat(cols - 1) * gridInterColumn
            let height = padding + headerHeight
                + CGFloat(rows) * cellHeight + CGFloat(max(rows - 1, 0)) * gridSpacing
            size = CGSize(width: width, height: height)
        case .list:
            // Sized from the configured rows + columns, exactly like the grid — so the
            // Rows / Columns steppers drive the drawer directly. It shows that many
            // (small) rows' worth of height and scrolls past it; it never balloons to
            // fit every item, nor shrinks to hide the configured size for a few items.
            let gridCellHeight = iconSize + 26
            let configuredCellsHeight = CGFloat(configuredRows) * gridCellHeight
                + CGFloat(max(configuredRows - 1, 0)) * gridSpacing
            let rows = max(1, Int((configuredCellsHeight / listRowHeight).rounded()))   // visible rows; scrolls beyond
            let height = padding + headerHeight + CGFloat(rows) * listRowHeight
            size = CGSize(width: listWidth(columns: columns, iconSize: iconSize), height: height)
        }
        // Reserve room for the filter field when the drawer shows one, so its extra
        // height doesn't push the items under a scroll bar.
        if searchable { size.height += searchBarHeight }
        return CGSize(width: min(size.width, visibleFrame.width - 16),
                      height: min(size.height, visibleFrame.height - 16))
    }
}
