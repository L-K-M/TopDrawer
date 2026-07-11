import XCTest
@testable import MacDring

final class FreshListerTests: XCTestCase {

    private func result(_ name: String, _ path: String, daysAgo: Double) -> SpotlightQuery.Result {
        SpotlightQuery.Result(url: URL(fileURLWithPath: path), name: name,
                              date: Date(timeIntervalSinceNow: -daysAgo * 86400))
    }

    func testItemsAreNewestFirstWithSequentialSlots() {
        let items = FreshLister.items(from: [
            result("old", "/old", daysAgo: 9),
            result("new", "/new", daysAgo: 1),
            result("mid", "/mid", daysAgo: 5),
        ])
        XCTAssertEqual(items.map(\.displayName), ["new", "mid", "old"])   // most-recently-added first
        XCTAssertEqual(items.map(\.slot), [0, 1, 2])
    }

    func testItemsResolveToTheirURL() throws {
        let url = URL(fileURLWithPath: "/Users/me/Downloads/report.pdf")
        let item = try XCTUnwrap(FreshLister.items(from: [result("report.pdf", url.path, daysAgo: 0)]).first)
        XCTAssertEqual(BookmarkResolver.url(for: item), url)
    }

    func testItemsCarryTheirDateAddedForTheListLayout() throws {
        let r = result("report.pdf", "/Users/me/Downloads/report.pdf", daysAgo: 2)
        let item = try XCTUnwrap(FreshLister.items(from: [r]).first)
        XCTAssertEqual(item.date, r.date)
    }

    func testCapsToLimit() {
        let many = (0..<(FreshLister.limit + 10)).map { result("f\($0)", "/f\($0)", daysAgo: Double($0)) }
        XCTAssertEqual(FreshLister.items(from: many).count, FreshLister.limit)
    }

    func testEmptyResultsProduceNoItems() {
        XCTAssertTrue(FreshLister.items(from: []).isEmpty)
    }

    func testScopesAreTheLandingZones() {
        let home = URL(fileURLWithPath: "/Users/me")
        let names = FreshLister.scopes(home: home).map(\.lastPathComponent)
        XCTAssertEqual(names, ["Downloads", "Desktop", "Documents"])
    }

    // MARK: merge (scan + Spotlight)

    func testMergeWithEmptySpotlightReturnsTheScanNewestFirst() {
        // Spotlight off: the direct scan alone backs the tab.
        let merged = FreshLister.merge([result("old", "/old", daysAgo: 9),
                                        result("new", "/new", daysAgo: 1)], [])
        XCTAssertEqual(merged.map(\.url.path), ["/new", "/old"])
    }

    func testMergeWithEmptyScanReturnsSpotlight() {
        let merged = FreshLister.merge([], [result("a", "/a", daysAgo: 2)])
        XCTAssertEqual(merged.map(\.url.path), ["/a"])
    }

    func testMergeInterleavesBothSourcesByDate() {
        let scan = [result("scanNew", "/scanNew", daysAgo: 1), result("scanOld", "/scanOld", daysAgo: 8)]
        let spot = [result("spotMid", "/spotMid", daysAgo: 4)]
        XCTAssertEqual(FreshLister.merge(scan, spot).map(\.url.path), ["/scanNew", "/spotMid", "/scanOld"])
    }

    func testMergeDeduplicatesSharedFilesByURL() {
        // A top-level file shows up in both sources; it appears once.
        let shared = "/Users/me/Downloads/report.pdf"
        let merged = FreshLister.merge([result("report", shared, daysAgo: 1)],
                                       [result("report", shared, daysAgo: 1)])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.url.path, shared)
    }
}
