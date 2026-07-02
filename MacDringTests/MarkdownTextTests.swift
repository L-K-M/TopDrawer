import XCTest
@testable import MacDring

final class MarkdownTextTests: XCTestCase {

    func testBlankLines() {
        XCTAssertEqual(MarkdownText.classify(""), .blank)
        XCTAssertEqual(MarkdownText.classify("   "), .blank)
    }

    func testHeadings() {
        XCTAssertEqual(MarkdownText.classify("# Title"), .heading(level: 1, text: "Title"))
        XCTAssertEqual(MarkdownText.classify("## Sub"), .heading(level: 2, text: "Sub"))
        XCTAssertEqual(MarkdownText.classify("### Deep"), .heading(level: 3, text: "Deep"))
        // 4–6 collapse to level 3 (we render at most three heading sizes).
        XCTAssertEqual(MarkdownText.classify("##### Five"), .heading(level: 3, text: "Five"))
    }

    func testHashWithoutSpaceOrTooManyIsParagraph() {
        XCTAssertEqual(MarkdownText.classify("#nospace"), .paragraph(text: "#nospace"))
        XCTAssertEqual(MarkdownText.classify("####### seven"), .paragraph(text: "####### seven"))
    }

    func testBullets() {
        XCTAssertEqual(MarkdownText.classify("- one"), .bullet(text: "one"))
        XCTAssertEqual(MarkdownText.classify("* two"), .bullet(text: "two"))
    }

    func testParagraphKeepsRawInlineMarkup() {
        XCTAssertEqual(MarkdownText.classify("Just **bold** and `code`."),
                       .paragraph(text: "Just **bold** and `code`."))
    }

    func testCheckboxes() {
        XCTAssertEqual(MarkdownText.classify("- [ ] buy milk"), .checkbox(isChecked: false, text: "buy milk"))
        XCTAssertEqual(MarkdownText.classify("- [x] done"), .checkbox(isChecked: true, text: "done"))
        XCTAssertEqual(MarkdownText.classify("- [X] also done"), .checkbox(isChecked: true, text: "also done"))
        // Not a well-formed checkbox → falls through to a plain bullet.
        XCTAssertEqual(MarkdownText.classify("- [] malformed"), .bullet(text: "[] malformed"))
    }

    func testTogglingCheckboxFlipsTheMarker() {
        let src = "- [ ] a\n- [x] b\nplain"
        XCTAssertEqual(MarkdownText.togglingCheckbox(in: src, lineIndex: 0), "- [x] a\n- [x] b\nplain")
        XCTAssertEqual(MarkdownText.togglingCheckbox(in: src, lineIndex: 1), "- [ ] a\n- [ ] b\nplain")
        // Non-checkbox line and out-of-range index are no-ops.
        XCTAssertEqual(MarkdownText.togglingCheckbox(in: src, lineIndex: 2), src)
        XCTAssertEqual(MarkdownText.togglingCheckbox(in: src, lineIndex: 9), src)
    }

    // MARK: Line splitting (normalized endings)

    func testLinesTreatsCRLFAsOneBreak() {
        XCTAssertEqual(MarkdownText.lines("a\r\nb\r\nc"), ["a", "b", "c"])
        XCTAssertEqual(MarkdownText.lines("a\rb"), ["a", "b"])
        XCTAssertEqual(MarkdownText.lines("a\u{2028}b\u{2029}c"), ["a", "b", "c"])
    }

    func testTogglingCheckboxInCRLFTextAddsNoPhantomBlankLines() {
        // Pasted Windows-style text: toggling must flip the right line and must not
        // grow the note by a blank line per CRLF (the old .newlines split did).
        let src = "- [ ] a\r\n- [ ] b\r\nplain"
        XCTAssertEqual(MarkdownText.togglingCheckbox(in: src, lineIndex: 1),
                       "- [ ] a\n- [x] b\nplain")
    }

    func testTogglingCheckboxIndexesMatchTheRenderedLines() {
        // The renderer and the toggler must split identically, or a tap lands on
        // the wrong line. Index 2 in CRLF text is "plain" for both.
        let src = "- [ ] a\r\n- [x] b\r\nplain"
        XCTAssertEqual(MarkdownText.lines(src)[2], "plain")
        XCTAssertEqual(MarkdownText.togglingCheckbox(in: src, lineIndex: 2),
                       src)   // not a checkbox → no-op
    }
}
