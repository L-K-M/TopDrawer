import XCTest
@testable import MacDring

final class ClipboardHistoryStoreTests: XCTestCase {
    func testRecordsNewestFirstAndPreservesExactText() {
        let history = ClipboardHistoryStore()
        history.record("first")
        let text = "  café\nsecond line\t"
        let date = Date(timeIntervalSince1970: 123)
        history.record(text, at: date)

        XCTAssertEqual(history.entries.map(\.text), [text, "first"])
        XCTAssertEqual(history.entries.first?.date, date)
    }

    func testDuplicateMovesToFrontWithoutChangingIdentity() throws {
        let history = ClipboardHistoryStore()
        history.record("first")
        let first = try XCTUnwrap(history.entries.first)
        history.record("second")
        let date = first.date.addingTimeInterval(60)
        history.record("first", at: date)

        XCTAssertEqual(history.entries.map(\.text), ["first", "second"])
        XCTAssertEqual(history.entries.first?.id, first.id)
        XCTAssertEqual(history.entries.first?.date, date)
        let later = date.addingTimeInterval(60)
        history.record("first", at: later)
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries.first?.id, first.id)
        XCTAssertEqual(history.entries.first?.date, later)
    }

    func testEvictsOldestWhenFull() {
        let history = ClipboardHistoryStore()
        for index in 0...ClipboardHistoryStore.limit { history.record("entry \(index)") }

        XCTAssertEqual(history.entries.count, ClipboardHistoryStore.limit)
        XCTAssertEqual(history.entries.first?.text, "entry \(ClipboardHistoryStore.limit)")
        XCTAssertEqual(history.entries.last?.text, "entry 1")
    }

    func testSkipsBlankAndOversizedTextWithoutTruncating() {
        let history = ClipboardHistoryStore()
        let boundary = String(repeating: "é", count: ClipboardHistoryStore.maximumTextBytes / 2)
        history.record(boundary)
        history.record(boundary + "x")
        history.record("")
        history.record(" \n\t")

        XCTAssertEqual(history.entries.map(\.text), [boundary])
    }

    func testRemoveAndClearAffectOnlyHistory() throws {
        let history = ClipboardHistoryStore()
        history.record("first")
        history.record("second")
        history.remove(id: try XCTUnwrap(history.entries.first?.id))
        XCTAssertEqual(history.entries.map(\.text), ["first"])
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertTrue(ClipboardHistoryStore().entries.isEmpty)
    }

    func testPreviewIsBoundedWithoutChangingCopiedText() throws {
        let history = ClipboardHistoryStore()
        let text = String(repeating: "🗂️", count: 200)
        history.record(text)
        let entry = try XCTUnwrap(history.entries.first)

        XCTAssertEqual(entry.preview, String(text.prefix(160)) + "…")
        XCTAssertEqual(entry.text, text)
    }

    func testPreviewAtTheLimitIsNotMarkedTruncated() throws {
        let history = ClipboardHistoryStore()
        let text = String(repeating: "a", count: 160)
        history.record(text)
        XCTAssertEqual(try XCTUnwrap(history.entries.first).preview, text)
    }
}
