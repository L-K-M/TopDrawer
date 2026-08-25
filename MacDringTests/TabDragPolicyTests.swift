import XCTest
@testable import MacDring

/// Encodes the drag-snap / magnetization and z-restack behavior at the point it was
/// lifted out of `TabController` (LP-10), so the pure move stays a pure move.
final class TabDragPolicyTests: XCTestCase {

    // MARK: Magnetize

    func testPositionSnapsToTheNearestQuarterGuideWithinTolerance() {
        // 0.26 is 0.01 from the ¼ guide — inside the 0.03 tolerance — so it locks on.
        let snap = TabDragPolicy.magnetize(position: 0.26, neighbors: [])
        XCTAssertEqual(snap.position, 0.25, accuracy: 1e-9)
        XCTAssertEqual(snap.guide, 0.25)
    }

    func testPositionStaysFreeWhenNoGuideIsCloseEnough() {
        // 0.4 is 0.1 from the nearest quarter guide (0.5) — well outside tolerance.
        let snap = TabDragPolicy.magnetize(position: 0.4, neighbors: [])
        XCTAssertEqual(snap.position, 0.4, accuracy: 1e-9, "a free drag keeps its raw position")
        XCTAssertNil(snap.guide, "nothing to lock onto")
    }

    func testPositionMagnetizesToANeighborFractionNotJustQuarterPoints() {
        // No quarter guide is near 0.4, but a neighbor sits at 0.42 (0.02 away) — the
        // neighbor fractions join the fixed guides, so the pill lines up with it.
        let snap = TabDragPolicy.magnetize(position: 0.4, neighbors: [0.42])
        XCTAssertEqual(snap.position, 0.42, accuracy: 1e-9)
        XCTAssertEqual(snap.guide, 0.42)
    }

    func testTheNearerOfAQuarterGuideAndANeighborWins() {
        // Both are within tolerance of 0.52: the ¼-point 0.5 (0.02 away) and a neighbor at
        // 0.53 (0.01 away). snappedPosition takes the nearest, so the neighbor wins — the
        // pill lines up with the tab rather than the coarser quarter grid.
        let snap = TabDragPolicy.magnetize(position: 0.52, neighbors: [0.53])
        XCTAssertEqual(snap.position, 0.53, accuracy: 1e-9, "nearest guide wins the tie-in-tolerance")
        XCTAssertEqual(snap.guide, 0.53)
    }

    // MARK: Alignment haptic (fire-once-on-lock transition)

    func testHapticFiresOnceWhenTheGuideLocksOn() {
        let t = TabDragPolicy.alignmentHaptic(current: 0.25, previous: nil)
        XCTAssertTrue(t.fire, "locking onto a guide from free fires the tap")
        XCTAssertEqual(t.guide, 0.25, "and the new guide is remembered")
    }

    func testHapticDoesNotRefireWhileStayingSnappedToTheSameGuide() {
        let t = TabDragPolicy.alignmentHaptic(current: 0.5, previous: 0.5)
        XCTAssertFalse(t.fire, "no buzz on every mouse-move while snapped")
        XCTAssertEqual(t.guide, 0.5)
    }

    func testHapticFiresWhenMovingBetweenTwoGuides() {
        let t = TabDragPolicy.alignmentHaptic(current: 0.5, previous: 0.25)
        XCTAssertTrue(t.fire, "crossing to a new guide is a fresh lock")
        XCTAssertEqual(t.guide, 0.5)
    }

    func testHapticIsSilentWhenThePillSlipsFree() {
        let t = TabDragPolicy.alignmentHaptic(current: nil, previous: 0.5)
        XCTAssertFalse(t.fire, "releasing a lock is not itself a tap")
        XCTAssertNil(t.guide, "and there is no guide to remember")
    }

    // MARK: Restack order (front to back)

    private func frame(x: CGFloat = 1400, y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 40, height: 44)
    }

    func testVerticalEdgeOrdersTopTabFrontmost() {
        // Right edge: the higher tab (greater maxY) draws in front, reading top→bottom.
        let top = UUID(), mid = UUID(), bot = UUID()
        let order = TabDragPolicy.restackOrder([
            .init(id: bot, restingFrame: frame(y: 100)),
            .init(id: top, restingFrame: frame(y: 800)),
            .init(id: mid, restingFrame: frame(y: 400)),
        ], edge: .right)
        XCTAssertEqual(order, [top, mid, bot])
    }

    func testHorizontalEdgeOrdersLeadingTabFrontmost() {
        // Top edge: the leftmost tab (smaller minX) draws in front, reading left→right.
        let left = UUID(), mid = UUID(), right = UUID()
        let order = TabDragPolicy.restackOrder([
            .init(id: right, restingFrame: frame(x: 900, y: 800)),
            .init(id: left, restingFrame: frame(x: 100, y: 800)),
            .init(id: mid, restingFrame: frame(x: 500, y: 800)),
        ], edge: .top)
        XCTAssertEqual(order, [left, mid, right])
    }

    func testLevelTabsBreakTiesByIdSoTheOrderIsStable() {
        // Two tabs at the same along-edge position: isFrontmost is nil, so id breaks the
        // tie deterministically (by uuidString), keeping the z-order stable across passes.
        let a = UUID(), b = UUID()
        let expected = [a, b].sorted { $0.uuidString < $1.uuidString }
        let order = TabDragPolicy.restackOrder([
            .init(id: a, restingFrame: frame(y: 400)),
            .init(id: b, restingFrame: frame(y: 400)),
        ], edge: .right)
        XCTAssertEqual(order, expected)
    }

    func testRestackOrderOfAnEmptyEdgeIsEmpty() {
        // The controller only calls this for groups of 2+, but the fold must stay total:
        // an empty (or single) input returns as-is so the `1..<count` re-seat loop is safe.
        XCTAssertEqual(TabDragPolicy.restackOrder([], edge: .right), [])
    }

    // MARK: Next stack order (newcomer slot)

    func testNextStackOrderIsZeroOnAnEmptyEdge() {
        XCTAssertEqual(TabDragPolicy.nextStackOrder(existingOrders: []), 0)
    }

    func testNextStackOrderIsOnePastTheHighest() {
        XCTAssertEqual(TabDragPolicy.nextStackOrder(existingOrders: [2, 0, 3, 1]), 4)
    }

    func testNextStackOrderIsCappedAtTheMaximum() {
        let max = PersistedLayoutBounds.maximumSlotOrOrder
        XCTAssertEqual(TabDragPolicy.nextStackOrder(existingOrders: [max]), max,
                       "the increment never runs off the top of the slot range")
    }
}
