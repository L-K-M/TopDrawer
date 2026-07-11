import XCTest
@testable import MacDring

/// Forward-compatibility: documents written by a **newer** Top Drawer (unknown
/// enum raw values, unreadable items) must degrade gracefully instead of
/// dropping tabs — a dropped tab is rewritten out of `launcher.json` by the
/// next autosave, which is permanent data loss.
final class LenientDecodingTests: XCTestCase {

    private func decodeDocument(_ json: String) throws -> LauncherDocument {
        try JSONDecoder().decode(LauncherDocument.self, from: Data(json.utf8))
    }

    private let anchor = #""anchor": { "displayUUID": "uuid-1", "edge": "right", "position": 0.5, "order": 0 }"#

    private func document(tabFields: String...) -> String {
        let tabs = tabFields
            .map { #"{ "title": "T", \#(anchor), \#($0) }"#  }
            .joined(separator: ", ")
        return #"{ "version": 1, "tabs": [ \#(tabs) ] }"#
    }

    // MARK: Unknown enum raw values keep the tab

    func testUnknownTabKindDegradesToItemsAndKeepsTheTab() throws {
        let doc = try decodeDocument(document(tabFields: #""kind": "shelf-from-the-future""#))
        XCTAssertEqual(doc.tabs.count, 1)
        XCTAssertEqual(doc.tabs[0].kind, .items)
        XCTAssertEqual(doc.tabs[0].title, "T")
    }

    func testUnknownFolderSortAndRecentsSourceFallBackToDefaults() throws {
        let doc = try decodeDocument(document(tabFields: #""folderSort": "constellation", "recentsSource": "telepathy""#))
        XCTAssertEqual(doc.tabs.count, 1)
        XCTAssertEqual(doc.tabs[0].folderSort, .name)
        XCTAssertEqual(doc.tabs[0].recentsSource, .macDring)
    }

    func testUnknownConcealmentDegradesToNeverAndKeepsTheTab() throws {
        let doc = try decodeDocument(document(tabFields: #""behavior": { "openOnHover": true, "concealment": "teleport" }"#))
        XCTAssertEqual(doc.tabs.count, 1)
        XCTAssertEqual(doc.tabs[0].behavior.concealment, .never)
        XCTAssertTrue(doc.tabs[0].behavior.openOnHover)   // known sibling fields survive
    }

    func testUnknownGlyphKindFallsBackToDefault() throws {
        let doc = try decodeDocument(document(tabFields: #""glyph": { "kind": "hologram", "value": "x" }"#))
        XCTAssertEqual(doc.tabs.count, 1)
        XCTAssertEqual(doc.tabs[0].glyph, .default)
    }

    // MARK: Items survive

    func testUnknownItemKindDegradesToFileKeepingNameURLAndSlot() throws {
        let items = #""items": [ { "kind": "stack", "displayName": "Future Stack", "url": "file:///tmp/x", "slot": 3 } ]"#
        let doc = try decodeDocument(document(tabFields: items))
        XCTAssertEqual(doc.tabs.count, 1)
        XCTAssertEqual(doc.tabs[0].items.count, 1)
        let item = try XCTUnwrap(doc.tabs[0].items.first)
        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.displayName, "Future Stack")
        XCTAssertEqual(item.url, URL(string: "file:///tmp/x"))
        XCTAssertEqual(item.slot, 3)
    }

    func testOneUnreadableItemIsDroppedWithoutKillingTheTab() throws {
        // The middle item's id is a number, which fails the UUID decode.
        let items = #""items": [ { "kind": "file", "displayName": "Good", "slot": 0 }, { "id": 12345, "kind": "file", "displayName": "Bad" }, { "kind": "folder", "displayName": "Also Good", "slot": 2 } ]"#
        let doc = try decodeDocument(document(tabFields: items))
        XCTAssertEqual(doc.tabs.count, 1)
        XCTAssertEqual(doc.tabs[0].items.map(\.displayName), ["Good", "Also Good"])
    }

    func testOneUnreadableGroupChildIsDroppedWithoutDroppingTheGroup() throws {
        let items = #""items": [ { "kind": "group", "displayName": "Work", "slot": 0, "children": [ { "kind": "file", "displayName": "Good", "slot": 0 }, { "id": 12345, "kind": "file", "displayName": "Bad", "slot": 1 }, { "kind": "folder", "displayName": "Also Good", "slot": 2 } ] } ]"#
        let doc = try decodeDocument(document(tabFields: items))

        XCTAssertEqual(doc.tabs[0].items.count, 1)
        let group = try XCTUnwrap(doc.tabs[0].items.first)
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.displayName, "Work")
        XCTAssertEqual(group.children.map(\.displayName), ["Good", "Also Good"])
    }

    func testUnreadableChildInTwoChildGroupPromotesSurvivorAtGroupSlot() throws {
        let items = #""items": [ { "kind": "group", "displayName": "Work", "slot": 7, "children": [ { "kind": "file", "displayName": "Good", "slot": 0 }, { "id": 12345, "kind": "file", "displayName": "Bad", "slot": 1 } ] } ]"#
        let doc = try decodeDocument(document(tabFields: items))

        XCTAssertEqual(doc.tabs[0].items.count, 1)
        let survivor = try XCTUnwrap(doc.tabs[0].items.first)
        XCTAssertEqual(survivor.kind, .file)
        XCTAssertEqual(survivor.displayName, "Good")
        XCTAssertEqual(survivor.slot, 7)
    }

    func testAllUnreadableGroupChildrenRemoveEmptyGroup() throws {
        let items = #""items": [ { "kind": "file", "displayName": "Keep", "slot": 0 }, { "kind": "group", "displayName": "Empty", "slot": 1, "children": [ { "id": 12345, "kind": "file", "displayName": "Bad" }, { "id": 67890, "kind": "folder", "displayName": "Also Bad" } ] } ]"#
        let doc = try decodeDocument(document(tabFields: items))

        XCTAssertEqual(doc.tabs[0].items.map(\.displayName), ["Keep"])
        XCTAssertFalse(doc.tabs[0].items.contains { $0.kind == .group })
    }

    func testMissingItemNameFallsBackToURL() throws {
        let items = #""items": [ { "kind": "file", "url": "file:///tmp/report.pdf" } ]"#
        let doc = try decodeDocument(document(tabFields: items))
        XCTAssertEqual(doc.tabs[0].items.count, 1)
        XCTAssertEqual(doc.tabs[0].items[0].displayName, "report.pdf")
    }

    // MARK: The one hard requirement that remains

    func testTabWithoutAnAnchorIsStillDropped() throws {
        let json = #"{ "version": 1, "tabs": [ { "title": "No Anchor" }, { "title": "T", \#(anchor) } ] }"#
        let doc = try decodeDocument(json)
        XCTAssertEqual(doc.tabs.count, 1)   // only the anchored tab survives
        XCTAssertEqual(doc.tabs[0].title, "T")
    }

    // MARK: Round trip

    func testDegradedTabReEncodesWithKnownValues() throws {
        let doc = try decodeDocument(document(tabFields: #""kind": "shelf-from-the-future""#))
        let data = try JSONEncoder().encode(doc)
        let reloaded = try JSONDecoder().decode(LauncherDocument.self, from: data)
        XCTAssertEqual(reloaded.tabs.count, 1)
        XCTAssertEqual(reloaded.tabs[0].kind, .items)
    }
}
