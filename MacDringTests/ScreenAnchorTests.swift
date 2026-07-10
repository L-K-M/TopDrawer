import XCTest
@testable import MacDring

final class ScreenAnchorTests: XCTestCase {

    func testPositionIsClampedOnInit() {
        XCTAssertEqual(ScreenAnchor(displayUUID: "x", edge: .right, position: 2).position, 1)
        XCTAssertEqual(ScreenAnchor(displayUUID: "x", edge: .right, position: -1).position, 0)
        XCTAssertEqual(ScreenAnchor(displayUUID: "x", edge: .right, position: 0.4).position, 0.4)
    }

    func testNonFinitePositionFallsBackToMidpoint() {
        // Non-finite inputs (NaN/±inf) map to the mid-point, not a clamp bound.
        XCTAssertEqual(ScreenAnchor.clampPosition(.nan), 0.5)
        XCTAssertEqual(ScreenAnchor.clampPosition(.infinity), 0.5)
        XCTAssertEqual(ScreenAnchor.clampPosition(-.infinity), 0.5)
    }

    func testCodableRoundTrip() throws {
        let anchor = ScreenAnchor(displayUUID: "ABC-123", edge: .bottom, position: 0.66, order: 3)
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(ScreenAnchor.self, from: data)
        XCTAssertEqual(decoded, anchor)
    }

    func testDecodeClampsCorruptedPositionAndDefaultsOrder() throws {
        let json = #"{"displayUUID":"D1","edge":"left","position":9.0}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ScreenAnchor.self, from: json)
        XCTAssertEqual(decoded.position, 1)      // clamped
        XCTAssertEqual(decoded.order, 0)         // defaulted
        XCTAssertEqual(decoded.edge, .left)
    }

    func testOrderBoundsMatchForInitializationMutationAndDecoding() throws {
        let maximum = PersistedLayoutBounds.maximumSlotOrOrder
        let cases = [
            (value: -1, expected: 0),
            (value: 0, expected: 0),
            (value: maximum, expected: maximum),
            (value: Int.max, expected: maximum),
        ]

        for value in cases {
            let anchor = ScreenAnchor(displayUUID: "D", edge: .left, position: 0.5, order: value.value)
            XCTAssertEqual(anchor.order, value.expected)

            var mutated = ScreenAnchor(displayUUID: "D", edge: .left, position: 0.5)
            mutated.order = value.value
            XCTAssertEqual(mutated.order, value.expected)

            let json = #"{"displayUUID":"D","edge":"left","position":0.5,"order":\#(value.value)}"#.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(ScreenAnchor.self, from: json)
            XCTAssertEqual(decoded.order, value.expected)
        }
    }

    func testNextOrderSaturatesAtMaximumWithoutOverflow() {
        let maximum = PersistedLayoutBounds.maximumSlotOrOrder
        XCTAssertEqual(PersistedLayoutBounds.nextOrder(after: nil), 0)
        XCTAssertEqual(PersistedLayoutBounds.nextOrder(after: maximum - 1), maximum)
        XCTAssertEqual(PersistedLayoutBounds.nextOrder(after: maximum), maximum)
        XCTAssertEqual(PersistedLayoutBounds.nextOrder(after: Int.max), maximum)
    }
}
