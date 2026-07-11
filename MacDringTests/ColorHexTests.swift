import XCTest
import AppKit
@testable import MacDring

final class ColorHexTests: XCTestCase {

    func testParsesSixAndEightDigitHex() {
        XCTAssertNotNil(NSColor(hex: "#0A84FF"))
        XCTAssertNotNil(NSColor(hex: "0A84FF"))      // leading # optional
        XCTAssertNotNil(NSColor(hex: "#0a84ffcc"))   // RRGGBBAA
    }

    func testRoundTripsThroughHexString() {
        let color = NSColor(hex: "#0A84FF")!
        XCTAssertEqual(color.hexString, "#0A84FF")
    }

    func testRejectsSignPrefixes() {
        // UInt64(_:radix:) accepts a leading "+", and the sign used to count as
        // a digit for the length check — "+84FF0" parsed as a wrong color.
        XCTAssertNil(NSColor(hex: "+84FF0"))
        XCTAssertNil(NSColor(hex: "#+84FF0"))
        XCTAssertNil(NSColor(hex: "-84FF0"))
    }

    func testRejectsNonHexAndWrongLengths() {
        XCTAssertNil(NSColor(hex: ""))
        XCTAssertNil(NSColor(hex: "#GGGGGG"))
        XCTAssertNil(NSColor(hex: "#12345"))      // 5 digits
        XCTAssertNil(NSColor(hex: "#1234567"))    // 7 digits
        XCTAssertNil(NSColor(hex: "not a color"))
    }
}
