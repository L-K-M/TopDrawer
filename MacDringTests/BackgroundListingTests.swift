import XCTest
@testable import MacDring

final class BackgroundListingTests: XCTestCase {
    func testReadsOffMainAndDeliversOnMain() {
        let listing = BackgroundListing<Int>()
        let delivered = expectation(description: "listing delivered")
        listing.load({
            XCTAssertFalse(Thread.isMainThread)
            return 42
        }) { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(value, 42)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)
    }

    func testNewRequestWinsEvenWhenOldReadFinishesLast() {
        let listing = BackgroundListing<String>()
        let entered = expectation(description: "old read started")
        let returned = expectation(description: "old read finished")
        let newest = expectation(description: "new listing delivered")
        let stale = expectation(description: "old listing discarded")
        stale.isInverted = true
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }

        listing.load({
            entered.fulfill()
            release.wait()
            returned.fulfill()
            return "old"
        }) { _ in stale.fulfill() }
        wait(for: [entered], timeout: 5)
        listing.load({ "new" }) { value in
            XCTAssertEqual(value, "new")
            newest.fulfill()
        }
        wait(for: [newest], timeout: 5)
        release.signal()
        wait(for: [returned], timeout: 5)
        wait(for: [stale], timeout: 0.2)
    }

    func testCancellationDiscardsALateReply() {
        let listing = BackgroundListing<Int>()
        let entered = expectation(description: "read started")
        let returned = expectation(description: "read finished")
        let delivered = expectation(description: "cancelled reply discarded")
        delivered.isInverted = true
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }

        listing.load({
            entered.fulfill()
            release.wait()
            returned.fulfill()
            return 1
        }) { _ in delivered.fulfill() }
        wait(for: [entered], timeout: 5)
        listing.cancel()
        release.signal()
        wait(for: [returned], timeout: 5)
        wait(for: [delivered], timeout: 0.2)
    }

    func testDrawerListingKeepsResolvedTargetWithItsItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("Document.txt"))
        let tab = Tab(title: "Folder", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "test", edge: .left, position: 0.5),
                      kind: .folder, folderURL: directory)
        let listing = DrawerListing.read(tab)
        XCTAssertEqual(listing.items.compactMap { $0.url?.lastPathComponent }, ["Document.txt"])
        XCTAssertEqual(listing.folderURL, directory)
        XCTAssertFalse(listing.truncated)
    }
}
