import XCTest
@testable import MacDring

final class DrawerNavigationTests: XCTestCase {
    private let items = [0, 2, 5, 6, 11].map { DrawerItem(kind: .file, displayName: "\($0)", slot: $0) }

    func testGridSkipsGapsAndKeepsColumnAcrossRows() {
        func next(_ index: Int, _ direction: DrawerNavigation.Direction) -> UUID? {
            DrawerNavigation.nextID(in: items, current: items[index].id, direction: direction, columns: 4, layout: .grid)
        }
        XCTAssertEqual(next(0, .right), items[1].id)
        XCTAssertEqual(next(1, .right), items[1].id)
        XCTAssertEqual(next(1, .down), items[3].id)
        XCTAssertEqual(next(3, .up), items[1].id)
        XCTAssertEqual(next(3, .down), items[4].id)
        XCTAssertEqual(next(4, .down), items[4].id)
        XCTAssertEqual(next(1, .left), items[0].id)
    }

    func testListPreservesRankedDisplayOrder() {
        let ranked = [items[3], items[0], items[1]]
        XCTAssertEqual(DrawerNavigation.nextID(in: ranked, current: items[3].id, direction: .down,
                                              columns: 4, layout: .list), items[0].id)
        XCTAssertEqual(DrawerNavigation.nextID(in: ranked, current: items[0].id, direction: .up,
                                              columns: 4, layout: .list), items[3].id)
    }

    func testEmptyAndInitialSelection() {
        XCTAssertNil(DrawerNavigation.nextID(in: [], current: nil, direction: .down, columns: 4, layout: .grid))
        XCTAssertEqual(DrawerNavigation.nextID(in: items, current: nil, direction: .down,
                                              columns: 4, layout: .grid), items.first?.id)
        XCTAssertEqual(DrawerNavigation.nextID(in: items, current: UUID(), direction: .up,
                                              columns: 4, layout: .grid), items.last?.id)
    }

    func testUnfilteredNavigationEntersGroupsAndLaunchesTheirChildren() {
        let model = DrawerModel()
        let group = DrawerItem(kind: .group, displayName: "Group", slot: 0, children: items)
        model.items = [group]
        var launched: [UUID] = []
        model.onLaunch = { launched.append($0.id) }
        model.moveSelection(.down)
        XCTAssertEqual(model.selectedItemID, group.id)
        model.launchSelection()
        XCTAssertEqual(model.openGroupID, group.id)
        XCTAssertNil(model.selectedItemID)
        XCTAssertTrue(launched.isEmpty)
        model.moveSelection(.right)
        model.moveSelection(.right)
        model.launchSelection()
        XCTAssertEqual(launched, [items[1].id])
    }

    func testSearchNavigationAndReturnKeepPrefixRanking() {
        let model = DrawerModel()
        let substring = DrawerItem(kind: .file, displayName: "A needle", slot: 0)
        let prefix = DrawerItem(kind: .file, displayName: "Needle first", slot: 5)
        model.items = [substring, prefix]
        var launched: [UUID] = []
        model.onLaunch = { launched.append($0.id) }
        model.searchQuery = "needle"
        model.launchSelection()
        model.moveSelection(.down)
        model.launchSelection()
        XCTAssertEqual(launched, [prefix.id, substring.id])
    }

    func testPreviewOnlyReceivesTheVisibleSelection() {
        let model = DrawerModel()
        model.items = items
        var previews: [UUID] = []
        model.onPreviewItem = { previews.append($0.id) }
        model.previewSelection()
        model.moveSelection(.down)
        model.previewSelection()
        model.items.removeFirst()
        model.previewSelection()
        XCTAssertEqual(previews, [items[0].id])
    }

    func testRemovalControlsDoNotOfferToDissolveALockedSibling() {
        let model = DrawerModel()
        let locked = DrawerItem(kind: .file, displayName: "Locked", isLocked: true, slot: 0)
        let unlocked = DrawerItem(kind: .file, displayName: "Unlocked", slot: 1)
        var group = DrawerItem(kind: .group, displayName: "Group", slot: 0, children: [locked, unlocked])
        model.items = [group]
        XCTAssertFalse(model.isEditingLocked(unlocked))
        XCTAssertTrue(model.isRemovalLocked(unlocked))
        group.children.append(DrawerItem(kind: .file, displayName: "Third", slot: 2))
        model.items = [group]
        XCTAssertFalse(model.isRemovalLocked(unlocked))
        group.isLocked = true
        model.items = [group]
        XCTAssertTrue(model.isEditingLocked(unlocked))
    }
}
