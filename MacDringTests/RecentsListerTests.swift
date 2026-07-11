import XCTest
@testable import MacDring

final class RecentsListerTests: XCTestCase {

    private func store() -> RecentsStore {
        RecentsStore(defaults: UserDefaults(suiteName: "recents-lister-\(UUID().uuidString)")!)
    }

    private func recentsTab() -> Tab {
        Tab(title: "R", colorHex: "#0A84FF",
            anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5), kind: .recents)
    }

    func testContentsMapsRecentsMostRecentFirst() {
        let s = store()
        s.record(RecentItem(url: URL(fileURLWithPath: "/Applications/Safari.app"),
                            kind: .application, name: "Safari", date: Date()))
        s.record(RecentItem(url: URL(string: "https://example.com")!,
                            kind: .url, name: "example", date: Date()))
        let items = RecentsLister.contents(of: recentsTab(), store: s)
        XCTAssertEqual(items.map(\.displayName), ["example", "Safari"])   // most recent first
        XCTAssertEqual(items.map(\.kind), [.url, .application])
        XCTAssertEqual(items.map(\.slot), [0, 1])
    }

    func testItemsResolveToTheirURL() throws {
        let s = store()
        let url = URL(fileURLWithPath: "/Users/me/Documents/report.pdf")
        s.record(RecentItem(url: url, kind: .file, name: "report.pdf", date: Date()))
        let item = try XCTUnwrap(RecentsLister.contents(of: recentsTab(), store: s).first)
        XCTAssertEqual(BookmarkResolver.url(for: item), url)
    }

    func testNonRecentsTabReturnsEmpty() {
        let tab = Tab(title: "I", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5), kind: .items)
        XCTAssertTrue(RecentsLister.contents(of: tab, store: store()).isEmpty)
    }

    // MARK: Source

    private func recentsTab(source: RecentsSource) -> Tab {
        var tab = recentsTab()
        tab.recentsSource = source
        return tab
    }

    func testSystemSourceHasNoSynchronousItems() {
        let s = store()
        s.record(RecentItem(url: URL(fileURLWithPath: "/a"), kind: .file, name: "a", date: Date()))
        // The system source is gathered asynchronously (Spotlight), so the synchronous
        // listing is empty — Top Drawer's own history is *not* included.
        XCTAssertTrue(RecentsLister.contents(of: recentsTab(source: .system), store: s).isEmpty)
    }

    func testBothSourceShowsMacDringHistorySynchronously() {
        let s = store()
        s.record(RecentItem(url: URL(fileURLWithPath: "/a"), kind: .file, name: "a", date: Date()))
        XCTAssertEqual(RecentsLister.contents(of: recentsTab(source: .both), store: s).map(\.displayName), ["a"])
    }

    func testItemsFromMapsRecordsWithSequentialSlots() {
        let items = RecentsLister.items(from: [
            RecentItem(url: URL(fileURLWithPath: "/a"), kind: .file, name: "a", date: Date()),
            RecentItem(url: URL(string: "https://x.com")!, kind: .url, name: "x", date: Date()),
        ])
        XCTAssertEqual(items.map(\.kind), [.file, .url])
        XCTAssertEqual(items.map(\.slot), [0, 1])
    }
}
