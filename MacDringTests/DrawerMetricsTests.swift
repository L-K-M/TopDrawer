import XCTest
@testable import MacDring

final class DrawerMetricsTests: XCTestCase {

    private let visible = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testGridWidthScalesWithColumns() {
        let two = DrawerMetrics.contentSize(itemCount: 8, maxSlot: 7, configuredRows: 2, layout: .grid, iconSize: 64, columns: 2, in: visible)
        let four = DrawerMetrics.contentSize(itemCount: 8, maxSlot: 7, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, in: visible)
        XCTAssertGreaterThan(four.width, two.width)
    }

    func testConfiguredRowsDriveHeight() {
        let short = DrawerMetrics.contentSize(itemCount: 1, maxSlot: 0, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, in: visible)
        let tall = DrawerMetrics.contentSize(itemCount: 1, maxSlot: 0, configuredRows: 6, layout: .grid, iconSize: 64, columns: 4, in: visible)
        XCTAssertGreaterThan(tall.height, short.height)
    }

    func testGridGrowsBeyondConfiguredRowsForItemsAndGaps() {
        // configured 2 rows, but an item parked at slot 20 → must grow.
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: 2, maxSlot: 20, itemCount: 2, columns: 4), 6)
        // configured 3 rows wins when items/slots are smaller.
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: 3, maxSlot: 3, itemCount: 4, columns: 4), 3)
        // never less than 1.
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: 1, maxSlot: -1, itemCount: 0, columns: 4), 1)
    }

    func testGridRowCountBoundsHostileValuesBeforeArithmetic() {
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: Int.max, maxSlot: Int.max,
                                                  itemCount: 0, columns: Int.max), 16)
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: -2, maxSlot: -2,
                                                  itemCount: 0, columns: -2), 1)

        let maximum = PersistedLayoutBounds.maximumSlotOrOrder
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: 16, maxSlot: maximum,
                                                  itemCount: 0, columns: 12),
                       maximum / 12 + 1)
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: 1, maxSlot: -1,
                                                  itemCount: Int.max, columns: 1),
                       PersistedLayoutBounds.maximumSlotCount)
    }

    func testRenderedGridDestinationsEndAtMaximumSlot() {
        XCTAssertEqual(DrawerMetrics.renderedGridSlotCount(rows: 2, columns: 4), 8)

        let maximum = PersistedLayoutBounds.maximumSlotOrOrder
        let rows = DrawerMetrics.gridRowCount(configuredRows: 16, maxSlot: maximum,
                                              itemCount: 0, columns: 12)
        let slotCount = DrawerMetrics.renderedGridSlotCount(rows: rows, columns: 12)
        XCTAssertEqual(slotCount, PersistedLayoutBounds.maximumSlotCount)
        XCTAssertEqual(slotCount - 1, maximum)
        XCTAssertEqual(DrawerMetrics.renderedGridSlotCount(rows: Int.max, columns: Int.max),
                       PersistedLayoutBounds.maximumSlotCount)
        XCTAssertEqual(DrawerMetrics.renderedGridSlotCount(rows: -1, columns: -1), 0)
    }

    func testContentSizeBoundsHostileDimensions() {
        let maximum = DrawerMetrics.contentSize(itemCount: 0, maxSlot: Int.max,
                                                configuredRows: Int.max, layout: .grid,
                                                iconSize: 64, columns: Int.max, in: visible)
        let upperBoundary = DrawerMetrics.contentSize(itemCount: 0, maxSlot: -1,
                                                      configuredRows: 16, layout: .grid,
                                                      iconSize: 64, columns: 12, in: visible)
        XCTAssertEqual(maximum, upperBoundary)

        let negative = DrawerMetrics.contentSize(itemCount: 0, maxSlot: -2,
                                                 configuredRows: Int.min, layout: .list,
                                                 iconSize: 64, columns: Int.min, in: visible)
        let lowerBoundary = DrawerMetrics.contentSize(itemCount: 0, maxSlot: -1,
                                                      configuredRows: 1, layout: .list,
                                                      iconSize: 64, columns: 1, in: visible)
        XCTAssertEqual(negative, lowerBoundary)
    }

    func testSizeIsClampedToScreen() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300)
        let size = DrawerMetrics.contentSize(itemCount: 200, maxSlot: 199, configuredRows: 50, layout: .grid, iconSize: 128, columns: 8, in: small)
        XCTAssertLessThanOrEqual(size.width, small.width - 16)
        XCTAssertLessThanOrEqual(size.height, small.height - 16)
    }

    func testEmptyDrawerHasPositiveSize() {
        let size = DrawerMetrics.contentSize(itemCount: 0, maxSlot: -1, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, in: visible)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testListSizeIsIndependentOfItemCount() {
        // The list is sized from the configured rows + columns, not the item count, so
        // its size stays put as items come and go (it scrolls past what fits).
        let few = DrawerMetrics.contentSize(itemCount: 3, maxSlot: 2, configuredRows: 2, layout: .list, iconSize: 48, columns: 4, in: visible)
        let many = DrawerMetrics.contentSize(itemCount: 30, maxSlot: 29, configuredRows: 2, layout: .list, iconSize: 48, columns: 4, in: visible)
        XCTAssertEqual(few.width, many.width, accuracy: 0.5)
        XCTAssertEqual(few.height, many.height, accuracy: 0.5)
    }

    func testListWidthTracksColumns() {
        // The Columns stepper widens the list (above the small one-column floor).
        let narrow = DrawerMetrics.contentSize(itemCount: 20, maxSlot: 19, configuredRows: 2, layout: .list, iconSize: 64, columns: 3, in: visible)
        let wide = DrawerMetrics.contentSize(itemCount: 20, maxSlot: 19, configuredRows: 2, layout: .list, iconSize: 64, columns: 6, in: visible)
        XCTAssertGreaterThan(wide.width, narrow.width)
    }

    func testListMetaColumnsShrinkWithWidth() {
        XCTAssertFalse(DrawerMetrics.listMetaColumns(forWidth: 240).size)   // narrow → date only
        XCTAssertTrue(DrawerMetrics.listMetaColumns(forWidth: 300).size)    // room for size
        XCTAssertFalse(DrawerMetrics.listMetaColumns(forWidth: 300).kind)
        XCTAssertTrue(DrawerMetrics.listMetaColumns(forWidth: 420).kind)    // room for all three
    }

    func testSmallIconListDropsKindToAvoidOverflow() {
        // 4 columns at the smallest icon (32) is narrow enough that Kind would overflow,
        // so it's dropped; a normal icon (64) at 4 columns fits the full table.
        let narrow = DrawerMetrics.listWidth(columns: 4, iconSize: 32)   // 298
        XCTAssertTrue(DrawerMetrics.listMetaColumns(forWidth: narrow).size)
        XCTAssertFalse(DrawerMetrics.listMetaColumns(forWidth: narrow).kind)
        let wide = DrawerMetrics.listWidth(columns: 4, iconSize: 64)     // 426
        XCTAssertTrue(DrawerMetrics.listMetaColumns(forWidth: wide).kind)
    }

    func testListWidthGrowsWithIconSize() {
        let small = DrawerMetrics.contentSize(itemCount: 4, maxSlot: 3, configuredRows: 2, layout: .list, iconSize: 32, columns: 4, in: visible)
        let large = DrawerMetrics.contentSize(itemCount: 4, maxSlot: 3, configuredRows: 2, layout: .list, iconSize: 128, columns: 4, in: visible)
        XCTAssertGreaterThan(large.width, small.width)
    }

    func testListHeightIsCappedToConfiguredSizeSoItScrolls() {
        // Past the configured capacity the list stops growing (the drawer keeps its
        // size and scrolls) — switching to List doesn't blow up the drawer.
        let many = DrawerMetrics.contentSize(itemCount: 1000, maxSlot: 999, configuredRows: 2, layout: .list, iconSize: 64, columns: 4, in: visible)
        let more = DrawerMetrics.contentSize(itemCount: 40, maxSlot: 39, configuredRows: 2, layout: .list, iconSize: 64, columns: 4, in: visible)
        XCTAssertEqual(many.height, more.height, accuracy: 0.5)
    }

    func testListHeightTracksConfiguredRows() {
        // More configured rows → a taller list (more rows visible before it scrolls).
        let short = DrawerMetrics.contentSize(itemCount: 1000, maxSlot: 999, configuredRows: 2, layout: .list, iconSize: 64, columns: 4, in: visible)
        let tall = DrawerMetrics.contentSize(itemCount: 1000, maxSlot: 999, configuredRows: 6, layout: .list, iconSize: 64, columns: 4, in: visible)
        XCTAssertGreaterThan(tall.height, short.height)
    }

    func testListFitsMoreSmallRowsThanGridCells() {
        // The list's compact rows mean it shows more entries than the grid's tall cells
        // do in the same configured height.
        let listCap = DrawerMetrics.contentSize(itemCount: 1000, maxSlot: 999, configuredRows: 3, layout: .list, iconSize: 64, columns: 4, in: visible)
        let gridRowsTall = DrawerMetrics.contentSize(itemCount: 12, maxSlot: 11, configuredRows: 3, layout: .grid, iconSize: 64, columns: 4, in: visible)
        // Both are sized from 3 configured rows; the list (small rows) is no taller than
        // the grid (tall cells) — it packs the same vertical budget more densely.
        XCTAssertLessThanOrEqual(listCap.height, gridRowsTall.height + 0.5)
    }

    func testSearchableDrawerReservesRoomForFilterField() {
        // A searchable drawer is taller by exactly the filter field's reserved height,
        // so the grid still fits without a scroll bar (the filter doesn't change width).
        let plain = DrawerMetrics.contentSize(itemCount: 8, maxSlot: 7, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, searchable: false, in: visible)
        let filtered = DrawerMetrics.contentSize(itemCount: 8, maxSlot: 7, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, searchable: true, in: visible)
        XCTAssertEqual(filtered.height, plain.height + DrawerMetrics.searchBarHeight, accuracy: 0.5)
        XCTAssertEqual(filtered.width, plain.width)
    }
}
