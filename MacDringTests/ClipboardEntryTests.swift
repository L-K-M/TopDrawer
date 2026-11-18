import XCTest
@testable import MacDring

final class ClipboardEntryTests: XCTestCase {

    private func entry(_ text: String) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), text: text, date: Date(timeIntervalSince1970: 1))
    }

    func testExcerptCentersAMatchNearTheEnd() {
        let text = String(repeating: "a", count: 300) + "NEEDLE" + String(repeating: "b", count: 100)
        let excerpt = entry(text).excerpt(matching: "needle")

        XCTAssertEqual(excerpt.matched, "NEEDLE")
        XCTAssertTrue(excerpt.leading.hasPrefix("…"))
        XCTAssertTrue(excerpt.trailing.hasSuffix("…"))
        XCTAssertTrue(excerpt.text.contains("NEEDLE"))
        XCTAssertLessThanOrEqual(excerpt.text.count, 162)
    }

    func testExcerptAtTheStartHasNoLeadingEllipsis() {
        let text = "NEEDLE" + String(repeating: "x", count: 300)
        let excerpt = entry(text).excerpt(matching: "needle")

        XCTAssertEqual(excerpt.leading, "")
        XCTAssertEqual(excerpt.matched, "NEEDLE")
        XCTAssertTrue(excerpt.text.hasPrefix("NEEDLE"))
        XCTAssertTrue(excerpt.trailing.hasSuffix("…"))
    }

    func testExcerptBeforeTheEndHasATrailingEllipsis() {
        let text = String(repeating: "x", count: 300) + "NEEDLE" + String(repeating: "y", count: 100)
        let excerpt = entry(text).excerpt(matching: "needle")

        XCTAssertEqual(excerpt.matched, "NEEDLE")
        XCTAssertTrue(excerpt.leading.hasPrefix("…"))
        XCTAssertTrue(excerpt.trailing.hasSuffix("…"))
    }

    func testExcerptAtTheVeryEndHasNoTrailingEllipsis() {
        let text = String(repeating: "x", count: 300) + "NEEDLE"
        let excerpt = entry(text).excerpt(matching: "needle")

        XCTAssertEqual(excerpt.matched, "NEEDLE")
        XCTAssertTrue(excerpt.leading.hasPrefix("…"))
        XCTAssertFalse(excerpt.trailing.hasSuffix("…"))
    }

    func testShortTextNeedsNoEllipses() {
        let excerpt = entry("hello world").excerpt(matching: "world")
        XCTAssertEqual(excerpt.leading, "hello ")
        XCTAssertEqual(excerpt.matched, "world")
        XCTAssertEqual(excerpt.trailing, "")
        XCTAssertEqual(excerpt.text, "hello world")
    }

    func testExcerptFallsBackToPreviewWithoutAMatchOrQuery() {
        let text = String(repeating: "q", count: 200)
        let e = entry(text)
        XCTAssertEqual(e.excerpt(matching: "absent").text, e.preview)
        XCTAssertEqual(e.excerpt(matching: "   ").text, e.preview)
    }

    func testExcerptMatchesDiacriticsInsensitively() {
        let text = String(repeating: "z", count: 200) + "café" + String(repeating: "z", count: 50)
        let excerpt = entry(text).excerpt(matching: "cafe")
        XCTAssertEqual(excerpt.matched, "café")
    }

    func testExcerptHandlesMultilineAndEmoji() {
        let text = "line1\n" + String(repeating: "😀", count: 40) + "\n"
            + String(repeating: "y", count: 200) + "TARGET"
        let excerpt = entry(text).excerpt(matching: "target")
        XCTAssertEqual(excerpt.matched, "TARGET")
        XCTAssertTrue(excerpt.text.contains("TARGET"))
        XCTAssertLessThanOrEqual(excerpt.text.count, 162)
    }
}
