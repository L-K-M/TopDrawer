import XCTest
@testable import Top Drawer

final class DrawerGroupingTests: XCTestCase {

    private func app(_ name: String, slot: Int = -1) -> DrawerItem {
        DrawerItem(kind: .application, displayName: name, slot: slot)
    }

    // MARK: Forming groups

    func testDroppingOneItemOntoAnotherWrapsBothInAGroupAtTargetsSlot() {
        let a = app("A", slot: 0), b = app("B", slot: 1), c = app("C", slot: 2)
        let result = DrawerGrouping.grouped([a, b, c], draggedID: c.id, ontoTargetID: a.id)!

        XCTAssertEqual(result.count, 2)                       // A+C collapsed into one group
        let group = result.first { $0.kind == .group }!
        XCTAssertEqual(group.slot, 0)                          // took A's slot
        XCTAssertEqual(group.children.map(\.id), [a.id, c.id]) // target first, then dragged
        XCTAssertEqual(Set(group.children.map(\.slot)), [0, 1])
        XCTAssertTrue(result.contains { $0.id == b.id })       // B untouched
        XCTAssertFalse(result.contains { $0.id == c.id })      // C is no longer top-level
    }

    func testDroppingOntoAnExistingGroupJoinsIt() {
        let a = app("A", slot: 0), b = app("B", slot: 1)
        let group = DrawerItem(kind: .group, displayName: "G", slot: 0, children: [a, b])
        let c = app("C", slot: 1)

        let result = DrawerGrouping.grouped([group, c], draggedID: c.id, ontoTargetID: group.id)!
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].children.map(\.id), [a.id, b.id, c.id])
        XCTAssertEqual(Set(result[0].children.map(\.slot)), [0, 1, 2])
    }

    func testDroppingOntoItselfOrDraggingAGroupIsNotGroupable() {
        let a = app("A", slot: 0), b = app("B", slot: 1)
        XCTAssertNil(DrawerGrouping.grouped([a, b], draggedID: a.id, ontoTargetID: a.id))

        let group = DrawerItem(kind: .group, displayName: "G", slot: 0, children: [app("X"), app("Y")])
        // A group can't be nested inside another item — caller should reorder instead.
        XCTAssertNil(DrawerGrouping.grouped([group, a], draggedID: group.id, ontoTargetID: a.id))
    }

    func testNonLaunchableItemsCannotBeGrouped() {
        // The Trash (and disks / cloud roots) keep their dedicated slot: they can be
        // neither the dragged item nor the target of a group.
        let app = app("Safari", slot: 0)
        let trash = DrawerItem(kind: .trash, displayName: "Trash", slot: 1)
        XCTAssertNil(DrawerGrouping.grouped([app, trash], draggedID: app.id, ontoTargetID: trash.id),
                     "grouping onto the Trash must be rejected")
        XCTAssertNil(DrawerGrouping.grouped([app, trash], draggedID: trash.id, ontoTargetID: app.id),
                     "grouping the Trash onto an app must be rejected")
    }

    func testIsGroupableGate() {
        XCTAssertTrue(DrawerGrouping.isGroupable(app("A")))
        XCTAssertTrue(DrawerGrouping.isGroupable(DrawerItem(kind: .url, displayName: "L", url: URL(string: "https://x.example"))))
        XCTAssertFalse(DrawerGrouping.isGroupable(DrawerItem(kind: .trash, displayName: "Trash")))
        XCTAssertFalse(DrawerGrouping.isGroupable(DrawerItem(kind: .disk, displayName: "Disk")))
        XCTAssertFalse(DrawerGrouping.isGroupable(DrawerItem(kind: .group, displayName: "G", children: [app("A"), app("B")])))
    }

    // MARK: Removing / dissolving

    func testRemovingFromAThreeChildGroupPopsToTopLevelAndKeepsTheGroup() {
        let a = app("A", slot: 0), b = app("B", slot: 1), c = app("C", slot: 2)
        let group = DrawerItem(kind: .group, displayName: "G", slot: 0, children: [a, b, c])
        let d = app("D", slot: 1)

        let result = DrawerGrouping.removingFromGroup([group, d], childID: b.id, groupID: group.id)
        let remaining = result.first { $0.kind == .group }!
        XCTAssertEqual(remaining.children.map(\.id), [a.id, c.id])
        XCTAssertTrue(result.contains { $0.id == b.id && $0.kind != .group })  // B now loose
    }

    func testRemovingUntilOneChildDissolvesTheGroup() {
        let a = app("A", slot: 0), b = app("B", slot: 1)
        let group = DrawerItem(kind: .group, displayName: "G", slot: 0, children: [a, b])

        let result = DrawerGrouping.removingFromGroup([group], childID: a.id, groupID: group.id)
        XCTAssertFalse(result.contains { $0.kind == .group })      // dissolved
        XCTAssertEqual(Set(result.map(\.id)), [a.id, b.id])        // both loose
    }

    func testDissolveSmallGroupsPromotesSingletonsAndDropsEmpties() {
        let x = app("X"), y = app("Y"), z = app("Z")
        let singleton = DrawerItem(kind: .group, displayName: "S", slot: 5, children: [x])
        let empty = DrawerItem(kind: .group, displayName: "E", slot: 6, children: [])
        let pair = DrawerItem(kind: .group, displayName: "P", slot: 7, children: [y, z])

        let result = DrawerGrouping.dissolvingSmallGroups([singleton, empty, pair])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.id == x.id && $0.slot == 5 })  // promoted, took group slot
        XCTAssertTrue(result.contains { $0.id == pair.id })              // pair kept
        XCTAssertFalse(result.contains { $0.id == empty.id })           // empty dropped
    }

    func testRemovingItemDeletesAChildAndDissolvesAPair() {
        let a = app("A", slot: 0), b = app("B", slot: 1)
        let group = DrawerItem(kind: .group, displayName: "G", slot: 4, children: [a, b])

        let result = DrawerGrouping.removingItem([group], id: a.id)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, b.id)
        XCTAssertEqual(result[0].slot, group.slot)
        XCTAssertFalse(result.contains { $0.id == a.id || $0.kind == .group })
    }

    func testRemovingItemKeepsAGroupWithTwoRemainingChildren() {
        let a = app("A", slot: 0), b = app("B", slot: 1), c = app("C", slot: 2)
        let group = DrawerItem(kind: .group, displayName: "G", slot: 4, children: [a, b, c])

        let result = DrawerGrouping.removingItem([group], id: b.id)

        XCTAssertEqual(result[0].kind, .group)
        XCTAssertEqual(result[0].children.map(\.id), [a.id, c.id])
    }

    func testUpdatingItemFindsAChildInAnyGroup() {
        let a = app("A"), b = app("B"), c = app("C"), d = app("D")
        let first = DrawerItem(kind: .group, displayName: "First", children: [a, b])
        let second = DrawerItem(kind: .group, displayName: "Second", children: [c, d])
        var updated = d
        updated.displayName = "Updated"

        let result = DrawerGrouping.updatingItem([first, second], with: updated)

        XCTAssertEqual(result[0], first)
        XCTAssertEqual(result[1].children.first { $0.id == d.id }?.displayName, "Updated")
    }

    func testRenaming() {
        let group = DrawerItem(kind: .group, displayName: "Old", slot: 0, children: [app("A"), app("B")])
        let result = DrawerGrouping.renaming([group], groupID: group.id, to: "Work")
        XCTAssertEqual(result[0].displayName, "Work")
    }

    // MARK: Model helpers

    func testFlattenedLaunchableReplacesGroupsWithChildren() {
        let a = app("A"), b = app("B"), c = app("C"), d = app("D")
        let group = DrawerItem(kind: .group, displayName: "G", slot: 1, children: [b, c])
        XCTAssertEqual([a, group, d].flattenedLaunchable().map(\.id), [a.id, b.id, c.id, d.id])
    }

    func testAssigningMissingSlotsNormalizesGroupChildren() {
        let a = app("A", slot: -1), b = app("B", slot: 5)     // duplicate/gappy child slots
        let c = app("C", slot: 5)
        let group = DrawerItem(kind: .group, displayName: "G", slot: -1, children: [a, b, c])
        let normalized = [group].assigningMissingSlots()
        let children = normalized[0].children
        XCTAssertTrue(children.allSatisfy { $0.slot >= 0 })
        XCTAssertEqual(Set(children.map(\.slot)).count, children.count)   // distinct
    }
}
