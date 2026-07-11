import XCTest
@testable import MacDring

final class BookmarkResolverTests: XCTestCase {

    private var tempFile: URL!

    override func setUpWithError() throws {
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdring-test-\(UUID().uuidString).txt")
        try "hello".data(using: .utf8)!.write(to: tempFile)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFile)
    }

    func testBookmarkRoundTripResolvesToSameFile() throws {
        let data = try XCTUnwrap(BookmarkResolver.makeBookmark(for: tempFile))
        let resolved = try XCTUnwrap(BookmarkResolver.resolve(data))
        XCTAssertEqual(resolved.url.lastPathComponent, tempFile.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.url.path))
    }

    func testFromFileURLProducesReachableItem() {
        let item = DrawerItem.fromFileURL(tempFile)
        XCTAssertEqual(item.kind, .file)
        XCTAssertFalse(BookmarkResolver.isBroken(item))
        XCTAssertEqual(BookmarkResolver.url(for: item)?.lastPathComponent, tempFile.lastPathComponent)
    }

    func testMissingFileItemIsBroken() {
        let missing = URL(fileURLWithPath: "/no/such/path/\(UUID().uuidString).txt")
        let item = DrawerItem(kind: .file, displayName: "Gone", bookmark: nil, url: missing)
        XCTAssertTrue(BookmarkResolver.isBroken(item))
    }

    func testURLItemIsNeverBroken() {
        let item = DrawerItem(kind: .url, displayName: "Site", url: URL(string: "https://example.com"))
        XCTAssertFalse(BookmarkResolver.isBroken(item))
        XCTAssertEqual(BookmarkResolver.url(for: item)?.absoluteString, "https://example.com")
    }

    func testFolderDetection() {
        let item = DrawerItem.fromFileURL(FileManager.default.temporaryDirectory)
        XCTAssertEqual(item.kind, .folder)
    }

    func testFromLinkAddsScheme() {
        XCTAssertEqual(DrawerItem.fromLink("example.com")?.url?.scheme, "https")
        XCTAssertEqual(DrawerItem.fromLink("  http://foo.test ")?.url?.scheme, "http")
        XCTAssertNil(DrawerItem.fromLink("   "))
    }
}
