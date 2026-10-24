import XCTest
@testable import MacDring

final class TabCyclingTests: XCTestCase {
    private func tab(_ order: Int, display: String = "Display", edge: Edge = .right) -> Tab {
        Tab(title: "\(order)", colorHex: "#123456",
            anchor: ScreenAnchor(displayUUID: display, edge: edge, position: 0.5, order: order))
    }

    func testCyclesInStableOrderAndWrapsWithinAvailableEdgePeers() {
        let a = tab(0), b = tab(1), otherEdge = tab(2, edge: .left), otherDisplay = tab(3, display: "Other")
        let parked = tab(4)
        let tabs = [parked, otherDisplay, b, otherEdge, a]
        let available = Set([a.id, b.id, otherEdge.id, otherDisplay.id])
        XCTAssertEqual(TabCycling.adjacentID(to: a.id, direction: .next, in: tabs, availableIDs: available), b.id)
        XCTAssertEqual(TabCycling.adjacentID(to: a.id, direction: .previous, in: tabs, availableIDs: available), b.id)
        XCTAssertEqual(TabCycling.adjacentID(to: b.id, direction: .next, in: tabs, availableIDs: available), a.id)
        XCTAssertNil(TabCycling.adjacentID(to: otherEdge.id, direction: .next, in: tabs, availableIDs: available))
        XCTAssertNil(TabCycling.adjacentID(to: UUID(), direction: .next, in: tabs, availableIDs: available))
    }

    func testTrackpadSwitchesOncePerGestureAndIgnoresMomentum() {
        var state = TabCycling.ScrollState()
        XCTAssertNil(state.consume(delta: 12, source: .trackpad, phase: .began, timestamp: 1))
        XCTAssertEqual(state.consume(delta: 12, source: .trackpad, phase: .changed, timestamp: 2), .previous)
        XCTAssertNil(state.consume(delta: 100, source: .trackpad, phase: .changed, timestamp: 3))
        XCTAssertNil(state.consume(delta: -100, source: .trackpad, phase: .momentum, timestamp: 4))
        XCTAssertNil(state.consume(delta: 0, source: .trackpad, phase: .ended, timestamp: 5))
        XCTAssertEqual(state.consume(delta: -24, source: .trackpad, phase: .began, timestamp: 6), .next)
    }

    func testCyclingFollowsSpatialOrderRatherThanStackingRecency() {
        for edge in Edge.allCases {
            var first = tab(0, edge: edge), last = tab(1, edge: edge), middle = tab(2, edge: edge)
            first.anchor.position = edge.isVertical ? 0.8 : 0.2
            middle.anchor.position = 0.5
            last.anchor.position = edge.isVertical ? 0.2 : 0.8
            let tabs = [last, first, middle]
            let available = Set(tabs.map(\.id))
            XCTAssertEqual(TabCycling.adjacentID(to: first.id, direction: .next, in: tabs, availableIDs: available), middle.id)
            XCTAssertEqual(TabCycling.adjacentID(to: first.id, direction: .previous, in: tabs, availableIDs: available), last.id)
        }
    }

    func testWheelIsRateLimitedAndRejectsInvalidSamples() {
        var state = TabCycling.ScrollState()
        XCTAssertEqual(state.consume(delta: -1, source: .wheel, phase: .changed, timestamp: 1), .next)
        XCTAssertNil(state.consume(delta: -1, source: .wheel, phase: .changed, timestamp: 1.1))
        XCTAssertEqual(state.consume(delta: 1, source: .wheel, phase: .changed, timestamp: 2), .previous)
        XCTAssertNil(state.consume(delta: .nan, source: .wheel, phase: .changed, timestamp: 3))
        XCTAssertNil(state.consume(delta: 1, source: .wheel, phase: .changed, timestamp: .infinity))
    }
}
