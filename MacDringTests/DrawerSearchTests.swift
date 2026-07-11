import XCTest
@testable import MacDring

final class DrawerSearchTests: XCTestCase {

    private func item(_ name: String, slot: Int) -> DrawerItem {
        DrawerItem(kind: .file, displayName: name, slot: slot)
    }

    // MARK: filter

    func testEmptyQueryReturnsAllInSlotOrder() {
        let items = [item("B", slot: 1), item("A", slot: 0)]
        XCTAssertEqual(DrawerSearch.filter(items, query: "   ").map(\.displayName), ["A", "B"])
    }

    func testSubstringCaseAndDiacriticInsensitive() {
        let items = [item("Safari", slot: 0), item("Café", slot: 1), item("Notes", slot: 2)]
        XCTAssertEqual(DrawerSearch.filter(items, query: "SAF").map(\.displayName), ["Safari"])   // case-insensitive
        XCTAssertEqual(DrawerSearch.filter(items, query: "cafe").map(\.displayName), ["Café"])    // diacritic-insensitive
    }

    func testPrefixMatchesRankBeforeInteriorThenBySlot() {
        let items = [item("Xcode", slot: 0), item("Apex", slot: 1), item("Pages", slot: 2), item("Preview", slot: 3)]
        // "p": prefix matches (Pages s2, Preview s3) before the interior match (Apex s1); Xcode has no 'p'.
        XCTAssertEqual(DrawerSearch.filter(items, query: "p").map(\.displayName), ["Pages", "Preview", "Apex"])
    }

    func testNoMatchesReturnsEmpty() {
        XCTAssertTrue(DrawerSearch.filter([item("Alpha", slot: 0)], query: "zzz").isEmpty)
    }

    // MARK: nextIndex

    func testNextIndexStartsAndClamps() {
        XCTAssertNil(DrawerSearch.nextIndex(count: 0, current: nil, down: true))
        XCTAssertEqual(DrawerSearch.nextIndex(count: 3, current: nil, down: true), 0)    // start at top
        XCTAssertEqual(DrawerSearch.nextIndex(count: 3, current: nil, down: false), 2)   // start at bottom
        XCTAssertEqual(DrawerSearch.nextIndex(count: 3, current: 0, down: true), 1)
        XCTAssertEqual(DrawerSearch.nextIndex(count: 3, current: 2, down: true), 2)      // clamp at end
        XCTAssertEqual(DrawerSearch.nextIndex(count: 3, current: 0, down: false), 0)     // clamp at start
    }

    // MARK: isFilterText

    func testIsFilterText() {
        XCTAssertTrue(DrawerSearch.isFilterText("a"))
        XCTAssertTrue(DrawerSearch.isFilterText("A1 -"))   // letters, digits, space, punctuation
        XCTAssertFalse(DrawerSearch.isFilterText(""))      // nothing typed
        XCTAssertFalse(DrawerSearch.isFilterText("\t"))    // control keys don't build the query
        XCTAssertFalse(DrawerSearch.isFilterText("\u{1B}")) // Esc
    }
}
