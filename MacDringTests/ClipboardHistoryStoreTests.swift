import XCTest
@testable import MacDring

final class ClipboardHistoryStoreTests: XCTestCase {
    private func makeStoreURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("history.json")
    }

    private func makeHistory() -> ClipboardHistoryStore {
        ClipboardHistoryStore(storeURL: makeStoreURL())
    }

    func testRecordsNewestFirstAndPreservesExactText() {
        let history = makeHistory()
        history.record("first")
        let text = "  café\nsecond line\t"
        let date = Date(timeIntervalSince1970: 123)
        history.record(text, at: date)

        XCTAssertEqual(history.entries.map(\.text), [text, "first"])
        XCTAssertEqual(history.entries.first?.date, date)
    }

    func testDuplicateMovesToFrontWithoutChangingIdentity() throws {
        let history = makeHistory()
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
        let history = makeHistory()
        for index in 0...ClipboardHistoryStore.limit { history.record("entry \(index)") }

        XCTAssertEqual(history.entries.count, ClipboardHistoryStore.limit)
        XCTAssertEqual(history.entries.first?.text, "entry \(ClipboardHistoryStore.limit)")
        XCTAssertEqual(history.entries.last?.text, "entry 1")
    }

    func testSkipsBlankAndOversizedTextWithoutTruncating() {
        let history = makeHistory()
        let boundary = String(repeating: "é", count: ClipboardHistoryStore.maximumTextBytes / 2)
        history.record(boundary)
        history.record(boundary + "x")
        history.record("")
        history.record(" \n\t")

        XCTAssertEqual(history.entries.map(\.text), [boundary])
    }

    func testRemoveAndClearAffectOnlyHistory() throws {
        let history = makeHistory()
        history.record("first")
        history.record("second")
        history.remove(id: try XCTUnwrap(history.entries.first?.id))
        XCTAssertEqual(history.entries.map(\.text), ["first"])
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertTrue(makeHistory().entries.isEmpty)
    }

    func testPreviewIsBoundedWithoutChangingCopiedText() throws {
        let history = makeHistory()
        let text = String(repeating: "🗂️", count: 200)
        history.record(text)
        let entry = try XCTUnwrap(history.entries.first)

        XCTAssertEqual(entry.preview, String(text.prefix(160)) + "…")
        XCTAssertEqual(entry.text, text)
    }

    func testPreviewAtTheLimitIsNotMarkedTruncated() throws {
        let history = makeHistory()
        let text = String(repeating: "a", count: 160)
        history.record(text)
        XCTAssertEqual(try XCTUnwrap(history.entries.first).preview, text)
    }

    func testHistoryIsNotPersistedByDefault() {
        let url = makeStoreURL()
        let history = ClipboardHistoryStore(storeURL: url)
        history.record("session only")
        history.saveNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        history.finishSession()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertTrue(ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts).entries.isEmpty)
    }

    func testQuitRestoresExactEntriesWhenRetentionIsEnabled() {
        let url = makeStoreURL()
        let history = ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts)
        history.record("first", at: Date(timeIntervalSince1970: 1))
        history.record("  café\nsecond line\t", at: Date(timeIntervalSince1970: 2))
        let snapshot = history.entries

        history.finishSession()
        XCTAssertTrue(history.entries.isEmpty)
        let restored = ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts)
        XCTAssertEqual(restored.entries, snapshot)
        XCTAssertNil(restored.persistenceError)
    }

    func testEnablingRetentionSavesCurrentHistoryAndDisablingDeletesOnlyTheArchive() {
        let url = makeStoreURL()
        let history = ClipboardHistoryStore(storeURL: url)
        history.record("already copied")
        let snapshot = history.entries
        history.setRetention(.acrossRestarts)
        XCTAssertEqual(ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts).entries, snapshot)

        history.record("pending write")
        history.setRetention(.sessionOnly)
        XCTAssertEqual(history.entries.map(\.text), ["pending write", "already copied"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        history.saveNow()
        history.finishSession()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testStartingWithoutRetentionDiscardsAnOldArchive() {
        let url = makeStoreURL()
        let history = ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts)
        history.record("old archive")
        history.saveNow()

        let session = ClipboardHistoryStore(storeURL: url)
        XCTAssertTrue(session.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAutomaticSaveStopsWhenRetentionIsDisabled() {
        let url = makeStoreURL()
        let history = ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts)
        history.record("saved automatically")
        let finished = expectation(description: "automatic save and disable complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts).entries, history.entries)
            history.record("pending at disable")
            history.setRetention(.sessionOnly)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
                XCTAssertEqual(history.entries.map(\.text), ["pending at disable", "saved automatically"])
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 5)
    }

    func testRemoveAndClearUpdateSavedHistoryWithoutResurrection() throws {
        let url = makeStoreURL()
        let history = ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts)
        history.record("first")
        history.record("second")
        history.remove(id: try XCTUnwrap(history.entries.last?.id))
        XCTAssertEqual(ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts).entries.map(\.text), ["second"])

        history.record("pending")
        history.clear()
        history.saveNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts).entries.isEmpty)
    }

    func testRestoredHistoryEnforcesTextIdentityAndCountLimits() throws {
        let url = makeStoreURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let first = ClipboardEntry(id: UUID(), text: "first", date: Date(timeIntervalSince1970: 1))
        let invalid = [
            ClipboardEntry(id: UUID(), text: first.text, date: Date()),
            ClipboardEntry(id: first.id, text: "duplicate id", date: Date()),
            ClipboardEntry(id: UUID(), text: " \n\t", date: Date()),
            ClipboardEntry(id: UUID(), text: String(repeating: "x", count: ClipboardHistoryStore.maximumTextBytes + 1), date: Date()),
        ]
        let extra = (0..<ClipboardHistoryStore.limit).map {
            ClipboardEntry(id: UUID(), text: "entry \($0)", date: Date())
        }
        try JSONEncoder().encode([first] + invalid + extra).write(to: url)

        let restored = ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts)
        XCTAssertEqual(restored.entries, [first] + extra.prefix(ClipboardHistoryStore.limit - 1))
        XCTAssertNil(restored.persistenceError)
    }

    func testUnreadableArchiveSurvivesQuitUntilExplicitlyCleared() throws {
        let url = makeStoreURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = Data("not JSON".utf8)
        try invalid.write(to: url)

        let history = ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts)
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNotNil(history.persistenceError)
        history.finishSession()
        XCTAssertEqual(try Data(contentsOf: url), invalid)
        history.record("temporary")
        history.saveNow()
        XCTAssertEqual(try Data(contentsOf: url), invalid)

        history.clear()
        XCTAssertNil(history.persistenceError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        history.record("after clear")
        history.saveNow()
        XCTAssertEqual(ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts).entries.map(\.text), ["after clear"])
    }

    func testSaveErrorsKeepMemoryAndRecoverOnRetry() throws {
        let url = makeStoreURL()
        let directory = url.deletingLastPathComponent()
        try Data().write(to: directory)
        let history = ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts)
        // Clear explicitly recovers from the unreadable path before trying to save.
        history.clear()
        history.record("keep in memory")
        history.saveNow()
        XCTAssertNotNil(history.persistenceError)
        XCTAssertEqual(history.entries.map(\.text), ["keep in memory"])

        try FileManager.default.removeItem(at: directory)
        history.saveNow()
        XCTAssertNil(history.persistenceError)
        XCTAssertEqual(ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts).entries, history.entries)
    }

    func testArchiveAndItsDirectoryAreOwnerOnlyAfterAtomicRewrites() throws {
        let url = makeStoreURL()
        let history = ClipboardHistoryStore(storeURL: url, retention: .acrossRestarts)
        for text in ["first", "second"] {
            history.record(text)
            history.saveNow()
            let file = try FileManager.default.attributesOfItem(atPath: url.path)
            let directory = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
            XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            XCTAssertEqual((directory[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        }
    }
}
