import XCTest
@testable import MacDring

final class ExternalDropTargetTests: XCTestCase {

    func testTopLevelPlacementContextIsExplicitAndOptional() {
        let topLevelItem = ExternalDropTarget.occupiedItem(
            id: UUID(), topLevelPlacementSlot: 4)
        let contextLocalItem = ExternalDropTarget.occupiedItem(
            id: UUID(), topLevelPlacementSlot: nil)
        let topLevelEmpty = ExternalDropTarget.emptySlot(
            localSlot: 4, topLevelPlacementSlot: 4)
        let groupEmpty = ExternalDropTarget.emptySlot(
            localSlot: 4, topLevelPlacementSlot: nil)

        XCTAssertEqual(topLevelItem.topLevelPlacementSlot, 4)
        XCTAssertNil(contextLocalItem.topLevelPlacementSlot)
        XCTAssertEqual(topLevelEmpty.topLevelPlacementSlot, 4)
        XCTAssertNil(groupEmpty.topLevelPlacementSlot)
    }

    func testGroupLocalEmptySlotsRemainDistinctFrameTargets() {
        let first = ExternalDropTarget.emptySlot(localSlot: 1, topLevelPlacementSlot: nil)
        let second = ExternalDropTarget.emptySlot(localSlot: 2, topLevelPlacementSlot: nil)

        XCTAssertNotEqual(first, second)
    }
}
