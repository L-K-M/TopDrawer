#if os(macOS)
import AppKit
import XCTest
@testable import MacDring

@MainActor
final class NotesEditorLinkInteractionTests: XCTestCase {
    func testPlainClickKeepsTheLinkAttributeAndRequestsCaretPlacement() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/note"))
        let storage = NSTextStorage(string: "Open link now")
        let range = (storage.string as NSString).range(of: "link")
        storage.addAttribute(.link, value: url, range: range)
        let interaction = NotesEditorLinkInteraction()

        XCTAssertEqual(interaction.activate(at: range.location, in: storage, as: .edit,
                                            clickCount: 1), .placeCaret)
        XCTAssertNotNil(storage.attribute(.link, at: range.location, effectiveRange: nil),
                        "a plain click must not strip the link — it is restyled, not unlinked")
        XCTAssertEqual(storage.string, "Open link now")
    }

    func testCommandClickOpensAfterAPlainClick() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/note"))
        let storage = NSTextStorage(string: "link")
        let range = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.link, value: url, range: range)
        let interaction = NotesEditorLinkInteraction()

        XCTAssertEqual(interaction.activate(at: range.location, in: storage, as: .edit,
                                            clickCount: 1), .placeCaret)
        // The attribute survived the edit click, so ⌘-click still resolves live.
        XCTAssertEqual(interaction.activate(at: range.location, in: storage, as: .open,
                                            clickCount: 1), .open(url))
    }

    func testCommandClickOpensOnlyWebLinks() throws {
        for scheme in ["https", "http", "file", "mailto", "custom"] {
            let url = try XCTUnwrap(URL(string: "\(scheme)://example.com/note"))
            let storage = NSTextStorage(string: "link")
            let range = NSRange(location: 0, length: storage.length)
            storage.addAttribute(.link, value: url, range: range)
            let interaction = NotesEditorLinkInteraction()

            let outcome = interaction.activate(at: range.location, in: storage, as: .open,
                                               clickCount: 1)
            if scheme == "http" || scheme == "https" {
                XCTAssertEqual(outcome, .open(url))
            } else {
                XCTAssertEqual(outcome, .placeCaret,
                               "non-web links can't be opened — a ⌘-click edits instead")
            }
            XCTAssertNotNil(storage.attribute(.link, at: range.location, effectiveRange: nil))
            XCTAssertEqual(storage.string, "link")
        }
    }

    func testOrdinaryTextPassesThrough() {
        let storage = NSTextStorage(string: "Plain text")
        let interaction = NotesEditorLinkInteraction()

        XCTAssertEqual(interaction.activate(at: 2, in: storage, as: .open, clickCount: 1),
                       .passthrough)
        XCTAssertEqual(interaction.activate(at: 0, in: NSTextStorage(), as: .edit, clickCount: 1),
                       .passthrough)
        XCTAssertEqual(interaction.activate(at: -1, in: storage, as: .open, clickCount: 1),
                       .passthrough)
        XCTAssertEqual(interaction.activate(at: Int.max, in: storage, as: .open, clickCount: 1),
                       .passthrough)
        XCTAssertEqual(storage.string, "Plain text")
    }

    func testMultiClickPassesThroughForWordAndLineSelection() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/note"))
        let storage = NSTextStorage(string: "link")
        let range = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.link, value: url, range: range)
        let interaction = NotesEditorLinkInteraction()

        // Double/triple clicks select, they don't navigate or park the caret.
        XCTAssertEqual(interaction.activate(at: range.location, in: storage, as: .edit,
                                            clickCount: 2), .passthrough)
        XCTAssertEqual(interaction.activate(at: range.location, in: storage, as: .edit,
                                            clickCount: 3), .passthrough)
    }

    func testClickJustBeforeTheLinkStartStillCounts() throws {
        // characterIndexForInsertion can land one past the leading glyph on a click
        // at the link's left edge — the insertion-1 candidate covers it.
        let url = try XCTUnwrap(URL(string: "https://example.com/note"))
        let storage = NSTextStorage(string: "a link")
        let range = (storage.string as NSString).range(of: "link")
        storage.addAttribute(.link, value: url, range: range)
        let interaction = NotesEditorLinkInteraction()

        XCTAssertEqual(interaction.activate(at: range.location + 1, in: storage, as: .edit,
                                            clickCount: 1), .placeCaret)
    }
}
#endif
