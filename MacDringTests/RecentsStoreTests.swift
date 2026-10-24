import XCTest
@testable import MacDring

final class RecentsStoreTests: XCTestCase {

    private let archiveKey = "recentItems"

    private func recent(_ name: String, _ path: String, kind: ItemKind = .file) -> RecentItem {
        RecentItem(url: URL(fileURLWithPath: path), kind: kind, name: name, date: Date())
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "recents-test-\(UUID().uuidString)")!
    }

    // MARK: Pure merging

    func testMergingPrependsAndDedupsByURL() {
        let merged = RecentsStore.merging([recent("A", "/a"), recent("B", "/b")],
                                          with: recent("A2", "/a"), limit: 10)
        XCTAssertEqual(merged.map(\.name), ["A2", "B"])   // /a moved to front (deduped), /b kept
    }

    func testMergingCapsToLimitKeepingNewest() {
        let items = (0..<5).map { recent("old\($0)", "/\($0)") }
        let merged = RecentsStore.merging(items, with: recent("new", "/new"), limit: 3)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.first?.name, "new")
    }

    // MARK: Merging sources (system Spotlight recents + Top Drawer history)

    private func dated(_ name: String, _ path: String, _ offset: TimeInterval) -> RecentItem {
        RecentItem(url: URL(fileURLWithPath: path), kind: .file, name: name, date: Date(timeIntervalSinceNow: offset))
    }

    func testDeduplicatedByURLOrdersByDateAndKeepsTheNewestDuplicate() {
        let merged = RecentsStore.deduplicatedByURL([
            dated("a-old", "/a", -100),
            dated("b", "/b", -50),
            dated("a-new", "/a", 0),
        ], limit: 10)
        XCTAssertEqual(merged.map(\.name), ["a-new", "b"])   // newest /a wins; sorted newest-first
    }

    func testDeduplicatedByURLCapsToLimit() {
        let items = (0..<5).map { dated("\($0)", "/\($0)", TimeInterval($0)) }   // larger offset = newer
        let merged = RecentsStore.deduplicatedByURL(items, limit: 2)
        XCTAssertEqual(merged.map(\.name), ["4", "3"])
    }

    // MARK: Store (injected defaults)

    func testRecordDedupsAndPersists() {
        let defaults = freshDefaults()
        let store = RecentsStore(defaults: defaults)
        store.record(recent("A", "/a"))
        store.record(recent("B", "/b"))
        store.record(recent("A-again", "/a"))
        XCTAssertEqual(store.items.map(\.name), ["A-again", "B"])

        let reloaded = RecentsStore(defaults: defaults)   // round-trips through UserDefaults
        XCTAssertEqual(reloaded.items.map(\.name), ["A-again", "B"])
    }

    func testClear() {
        let store = RecentsStore(defaults: freshDefaults())
        store.record(recent("A", "/a"))
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: Lenient loading (one bad record must not wipe the history)

    /// Writes raw JSON into the store's UserDefaults key, bypassing the encoder.
    private func writeRaw(_ json: String, to defaults: UserDefaults) {
        defaults.set(Data(json.utf8), forKey: archiveKey)
    }

    func testRecordingPreservesUnreadableArchiveAcrossSessions() {
        let defaults = freshDefaults()
        for json in ["[", #"{"unexpected":"object"}"#] {
            let archive = Data(json.utf8)
            defaults.set(archive, forKey: archiveKey)

            let store = RecentsStore(defaults: defaults)
            XCTAssertTrue(store.items.isEmpty)
            store.record(recent("Session item", "/session"))
            XCTAssertEqual(store.items.map(\.name), ["Session item"])
            XCTAssertEqual(defaults.data(forKey: archiveKey), archive)

            let reloaded = RecentsStore(defaults: defaults)
            reloaded.record(recent("Next session", "/next"))
            XCTAssertEqual(defaults.data(forKey: archiveKey), archive)
        }
    }

    func testExplicitClearAllowsReplacingUnreadableArchive() {
        let defaults = freshDefaults()
        writeRaw("[", to: defaults)
        let store = RecentsStore(defaults: defaults)
        store.record(recent("Before clear", "/before"))

        store.clear()
        XCTAssertEqual(defaults.data(forKey: archiveKey), Data("[]".utf8))
        XCTAssertTrue(RecentsStore(defaults: defaults).items.isEmpty)

        store.record(recent("After clear", "/after"))
        XCTAssertEqual(RecentsStore(defaults: defaults).items.map(\.name), ["After clear"])
    }

    func testUnknownKindDegradesToFileInsteadOfWipingHistory() {
        let defaults = freshDefaults()
        writeRaw("""
        [{"url":"file:///a","kind":"hologram","name":"A","date":0},
         {"url":"file:///b","kind":"file","name":"B","date":0}]
        """, to: defaults)
        let store = RecentsStore(defaults: defaults)
        XCTAssertEqual(store.items.map(\.name), ["A", "B"])   // both survive
        XCTAssertEqual(store.items.first?.kind, .file)        // unknown kind degraded
    }

    func testRecordMissingItsURLIsDroppedAloneNotTheWholeHistory() {
        let defaults = freshDefaults()
        writeRaw("""
        [{"kind":"file","name":"no-url","date":0},
         {"url":"file:///b","kind":"file","name":"B","date":0}]
        """, to: defaults)
        let store = RecentsStore(defaults: defaults)
        XCTAssertEqual(store.items.map(\.name), ["B"])
    }

    func testMissingNameFallsBackToLastPathComponent() {
        let defaults = freshDefaults()
        writeRaw(#"[{"url":"file:///deep/Report.pdf","kind":"file","date":0}]"#, to: defaults)
        let store = RecentsStore(defaults: defaults)
        XCTAssertEqual(store.items.first?.name, "Report.pdf")
    }
}
