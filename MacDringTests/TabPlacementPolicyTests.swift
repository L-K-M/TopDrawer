import XCTest
@testable import MacDring

/// Encodes TabController's placement behavior at the point it was lifted into
/// `TabPlacementPolicy` (LP-09), so the pure move stays a pure move.
final class TabPlacementPolicyTests: XCTestCase {

    // MARK: Reconcile placement

    func testPlacementPrefersTheTabsOwnDisplayWhenConnected() {
        // Own display present → land there, whatever the policy or main display.
        for policy in DisconnectPolicy.allCases {
            XCTAssertEqual(TabPlacementPolicy.placement(anchoredDisplay: 7, mainDisplay: 1, disconnectPolicy: policy),
                           .place(7))
        }
    }

    func testPlacementMovesToMainWhenDisconnectedUnderMoveToMain() {
        XCTAssertEqual(TabPlacementPolicy.placement(anchoredDisplay: Int?.none, mainDisplay: 1,
                                                    disconnectPolicy: .moveToMain),
                       .place(1))
    }

    func testPlacementParksWhenDisconnectedUnderPark() {
        // Park policy keeps the tab off-screen even though a main display exists.
        XCTAssertEqual(TabPlacementPolicy.placement(anchoredDisplay: Int?.none, mainDisplay: 1,
                                                    disconnectPolicy: .park),
                       .park)
    }

    func testPlacementParksUnderMoveToMainWhenThereIsNoMainDisplay() {
        XCTAssertEqual(TabPlacementPolicy.placement(anchoredDisplay: Int?.none, mainDisplay: Int?.none,
                                                    disconnectPolicy: .moveToMain),
                       .park)
    }

    // MARK: De-overlap fold

    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    /// A pill on the right (vertical) edge at a given y.
    private func input(_ id: UUID, order: Int, position: Double, y: CGFloat,
                       ownDisplay: Bool = true) -> TabPlacementPolicy.DeOverlapInput {
        .init(id: id, order: order, position: position,
              restingFrame: CGRect(x: 1400, y: y, width: 40, height: 44), isOnOwnDisplay: ownDisplay)
    }

    func testASingleTabIsUnchangedAndNotPersisted() {
        let id = UUID()
        let results = TabPlacementPolicy.deOverlap([input(id, order: 0, position: 0.5, y: 400)],
                                                   edge: .right, gap: EdgeLayout.minTabGap, in: visible)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].settledFrame, CGRect(x: 1400, y: 400, width: 40, height: 44))
        XCTAssertNil(results[0].persistedPosition, "an untouched tab must not be persisted")
    }

    func testResultsComeBackInStackingOrderSoTheTopOrderTabYields() {
        // Three well-separated tabs: none overlaps, so all keep their frames — but the
        // fold still returns them in (order, position, id) order, which is the order the
        // snap would place them in, i.e. the last one is the one that would yield.
        let a = UUID(), b = UUID(), c = UUID()
        let results = TabPlacementPolicy.deOverlap([
            input(b, order: 2, position: 0.5, y: 100),
            input(a, order: 1, position: 0.5, y: 500),
            input(c, order: 2, position: 0.9, y: 300),
        ], edge: .right, gap: EdgeLayout.minTabGap, in: visible)
        XCTAssertEqual(results.map(\.id), [a, b, c], "order, then position, then id")
    }

    func testAnOverlappingOwnDisplayTabSnapsAndPersists() {
        // Two pills at the same spot: the lower-order one holds, the higher-order one is
        // displaced and — being on its own display — persists its new position.
        let held = UUID(), yields = UUID()
        let results = TabPlacementPolicy.deOverlap([
            input(held, order: 0, position: 0.5, y: 400),
            input(yields, order: 1, position: 0.5, y: 400),
        ], edge: .right, gap: EdgeLayout.minTabGap, in: visible)

        let heldResult = try! XCTUnwrap(results.first { $0.id == held })
        let yieldsResult = try! XCTUnwrap(results.first { $0.id == yields })
        XCTAssertEqual(heldResult.settledFrame.origin.y, 400, "the tab already there stays put")
        XCTAssertNil(heldResult.persistedPosition, "it didn't move, so nothing to persist")
        XCTAssertNotEqual(yieldsResult.settledFrame.origin.y, 400, "the newcomer is displaced")
        XCTAssertNotNil(yieldsResult.persistedPosition, "an own-display tab that moved persists")
    }

    func testAGuestThatMovesIsNotPersisted() {
        // Same displacement, but the newcomer is a move-to-main guest: it de-overlaps on
        // screen yet must not overwrite the anchor it has to restore to.
        let held = UUID(), guest = UUID()
        let results = TabPlacementPolicy.deOverlap([
            input(held, order: 0, position: 0.5, y: 400),
            input(guest, order: 1, position: 0.5, y: 400, ownDisplay: false),
        ], edge: .right, gap: EdgeLayout.minTabGap, in: visible)

        let guestResult = try! XCTUnwrap(results.first { $0.id == guest })
        XCTAssertNotEqual(guestResult.settledFrame.origin.y, 400, "the guest is still de-overlapped on screen")
        XCTAssertNil(guestResult.persistedPosition, "but a guest never persists — stable restore is sacred")
    }
}
