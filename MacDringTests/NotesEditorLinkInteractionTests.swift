#if os(macOS)
import AppKit
import XCTest
@testable import MacDring

@MainActor
final class NotesEditorLinkInteractionTests: XCTestCase {
    func testPlainClickThenCommandClickOpensWithoutAnEngineRestyle() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/note"))
        let storage = NSTextStorage(string: "Open link now")
        let range = (storage.string as NSString).range(of: "link")
        storage.addAttribute(.link, value: url, range: range)
        var interaction = NotesEditorLinkInteraction()

        XCTAssertNil(interaction.activate(at: range.location, in: storage, as: .edit))
        XCTAssertNil(storage.attribute(.link, at: range.location, effectiveRange: nil),
                     "A native editing gesture must not open the link")
        XCTAssertEqual(storage.string, "Open link now")
        XCTAssertEqual(interaction.activate(at: range.location, in: storage, as: .open), url)
    }

    func testCommandClickOpensOnlyWebLinks() throws {
        for scheme in ["https", "http", "file", "mailto", "custom"] {
            let url = try XCTUnwrap(URL(string: "\(scheme)://example.com/note"))
            let storage = NSTextStorage(string: "link")
            let range = NSRange(location: 0, length: storage.length)
            storage.addAttribute(.link, value: url, range: range)
            var interaction = NotesEditorLinkInteraction()

            let opened = interaction.activate(at: range.location, in: storage, as: .open)
            if scheme == "http" || scheme == "https" {
                XCTAssertEqual(opened, url)
            } else {
                XCTAssertNil(opened)
                XCTAssertNil(storage.attribute(.link, at: range.location, effectiveRange: nil))
            }
            XCTAssertEqual(storage.string, "link")
        }
    }

    func testOrdinaryTextHasNoLinkAction() {
        let storage = NSTextStorage(string: "Plain text")
        var interaction = NotesEditorLinkInteraction()

        XCTAssertNil(interaction.activate(at: 2, in: storage, as: .open))
        XCTAssertNil(interaction.activate(at: 0, in: NSTextStorage(), as: .edit))
        XCTAssertEqual(storage.string, "Plain text")
    }
}
#endif
