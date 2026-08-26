import XCTest
@testable import TopDrawerDaemon

/// Pure tests for the xbel parser, the recents window/sort, the file location, and the
/// launcher-tab lookup — the LP-18 acceptance's "xbel fixture tests". Cross-platform:
/// no real `recently-used.xbel`, `statx`, or bus is touched.
final class LinuxRecentsTests: XCTestCase {

    private let xbel = """
    <?xml version="1.0" encoding="UTF-8"?>
    <xbel version="1.0">
      <bookmark href="file:///home/alice/Documents/report.pdf" added="2026-08-01T09:00:00Z" modified="2026-08-02T09:00:00Z" visited="2026-08-20T12:00:00Z"/>
      <bookmark href="file:///home/alice/Downloads/pic%20one.png" added="2026-08-01T09:00:00Z" visited="2026-08-25T08:30:00Z"/>
      <bookmark href="http://example.com/not-a-file" visited="2026-08-25T09:00:00Z"/>
      <bookmark href="file:///home/alice/old.txt" visited="2020-01-01T00:00:00Z"/>
    </xbel>
    """

    // MARK: - Parser

    func testParseExtractsFileBookmarksWithVisitedDate() {
        let hits = XbelParser.parse(xbel)
        XCTAssertEqual(hits.count, 3, "three file:// bookmarks; the http one is skipped")
        let byName = Dictionary(uniqueKeysWithValues: hits.map { ($0.name, $0) })
        XCTAssertNotNil(byName["report.pdf"])
        // %20 decodes back to a space in the path.
        XCTAssertEqual(byName["pic one.png"]?.url.path, "/home/alice/Downloads/pic one.png")
    }

    func testParseSkipsNonFileHrefs() {
        XCTAssertFalse(XbelParser.parse(xbel).contains { $0.url.absoluteString.contains("example.com") })
    }

    func testParseIgnoresGarbage() {
        XCTAssertTrue(XbelParser.parse("not xml at all").isEmpty)
        XCTAssertTrue(XbelParser.parse("").isEmpty)
    }

    // MARK: - Window / sort

    func testHitsAreWithinWindowNewestFirst() {
        // now just after the newest visit; the 2020 entry is outside the 90-day window.
        let now = ISO8601DateFormatter().date(from: "2026-08-25T10:00:00Z")!
        let hits = RecentlyUsedFile.hits(xbel: xbel, limit: 10, now: now)
        XCTAssertEqual(hits.map(\.name), ["pic one.png", "report.pdf"],
                       "newest first, and old.txt (2020) dropped as stale")
    }

    func testHitsRespectLimit() {
        let now = ISO8601DateFormatter().date(from: "2026-08-25T10:00:00Z")!
        XCTAssertEqual(RecentlyUsedFile.hits(xbel: xbel, limit: 1, now: now).map(\.name), ["pic one.png"])
    }

    // MARK: - Location

    func testLocationHonorsXDGDataHome() {
        let url = RecentlyUsedFile.location(environment: ["XDG_DATA_HOME": "/custom"],
                                            home: URL(fileURLWithPath: "/home/alice"))
        XCTAssertEqual(url.path, "/custom/recently-used.xbel")
    }

    func testLocationFallsBackToLocalShare() {
        let url = RecentlyUsedFile.location(environment: [:], home: URL(fileURLWithPath: "/home/alice"))
        XCTAssertEqual(url.path, "/home/alice/.local/share/recently-used.xbel")
    }

    func testLocationIgnoresRelativeXDGDataHome() {
        let url = RecentlyUsedFile.location(environment: ["XDG_DATA_HOME": "rel"],
                                            home: URL(fileURLWithPath: "/home/alice"))
        XCTAssertEqual(url.path, "/home/alice/.local/share/recently-used.xbel")
    }

    // MARK: - Launcher-tab lookup

    func testLauncherTabsFindByID() {
        let json = #"{"version":1,"tabs":[{"id":"A","kind":"recents","recentsSource":"system"},{"id":"B","kind":"fresh"}]}"#
        XCTAssertEqual(LauncherTabs.find(id: "A", in: json)?.kind, "recents")
        XCTAssertEqual(LauncherTabs.find(id: "A", in: json)?.recentsSource, "system")
        XCTAssertEqual(LauncherTabs.find(id: "B", in: json)?.kind, "fresh")
        XCTAssertNil(LauncherTabs.find(id: "B", in: json)?.recentsSource)
        XCTAssertNil(LauncherTabs.find(id: "Z", in: json))
        XCTAssertTrue(LauncherTabs.all(in: "not json").isEmpty)
    }

    #if os(Linux)
    func testBirthTimeIsNilForAMissingFile() {
        XCTAssertNil(linuxDateAdded(URL(fileURLWithPath: "/no/such/file/anywhere")))
    }

    func testLinuxDateAddedReturnsADateForARealFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("btime-\(UUID().uuidString).txt")
        try "x".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Either statx birth time or the mtime fallback must yield a date.
        XCTAssertNotNil(linuxDateAdded(tmp))
    }
    #endif
}
