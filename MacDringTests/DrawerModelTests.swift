import XCTest
@testable import MacDring

final class DrawerModelTests: XCTestCase {

    func testItemAtSlotFindsByGridSlotIncludingGaps() {
        let model = DrawerModel()
        let a = DrawerItem(kind: .file, displayName: "A", slot: 0)
        let b = DrawerItem(kind: .file, displayName: "B", slot: 3)   // gap at 1, 2
        model.items = [a, b]

        XCTAssertEqual(model.item(atSlot: 0)?.id, a.id)
        XCTAssertEqual(model.item(atSlot: 3)?.id, b.id)
        XCTAssertNil(model.item(atSlot: 1))
        XCTAssertNil(model.item(atSlot: 2))
    }

    // MARK: Groups

    func testVisibleItemsFollowsTheOpenGroup() {
        let model = DrawerModel()
        let a = DrawerItem(kind: .file, displayName: "A", slot: 0)
        let b = DrawerItem(kind: .file, displayName: "B", slot: 1)
        let group = DrawerItem(kind: .group, displayName: "G", slot: 0, children: [a, b])
        model.items = [group]

        XCTAssertEqual(model.visibleItems.map(\.id), [group.id])   // top level
        model.openGroupID = group.id
        XCTAssertEqual(Set(model.visibleItems.map(\.id)), [a.id, b.id])   // inside the group
        XCTAssertEqual(model.visibleItem(atSlot: 1)?.id, b.id)
    }

    func testOpenGroupIDClearsWhenTheGroupDisappears() {
        // Popping a child until the group dissolves reassigns `items`; the open-group id
        // must not linger pointing at a group that's gone (else reorder/dwell misroute).
        let model = DrawerModel()
        let a = DrawerItem(kind: .file, displayName: "A", slot: 0)
        let b = DrawerItem(kind: .file, displayName: "B", slot: 1)
        let group = DrawerItem(kind: .group, displayName: "G", slot: 0, children: [a, b])
        model.items = [group]
        model.openGroupID = group.id

        // Simulate the dissolve: the store replaces items with two loose ones.
        model.items = [a, b]
        XCTAssertNil(model.openGroupID)
        XCTAssertNil(model.openGroup)
        XCTAssertEqual(Set(model.visibleItems.map(\.id)), [a.id, b.id])   // back at the top level
    }

    func testOpenGroupIDSurvivesAReorderWithinTheGroup() {
        // A reorder inside the group replaces `items` but the group still exists — the
        // user must stay inside it.
        let model = DrawerModel()
        let a = DrawerItem(kind: .file, displayName: "A", slot: 0)
        let b = DrawerItem(kind: .file, displayName: "B", slot: 1)
        let group = DrawerItem(kind: .group, displayName: "G", slot: 0, children: [a, b])
        model.items = [group]
        model.openGroupID = group.id

        // Same group id, children reordered.
        var reordered = group
        reordered.children = [b, a]
        model.items = [reordered]
        XCTAssertEqual(model.openGroupID, group.id)
        XCTAssertNotNil(model.openGroup)
    }
}
