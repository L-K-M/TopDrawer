import XCTest
@testable import MacDring

final class DrawerItemTests: XCTestCase {

    func testFromDroppedURLMakesLinkItemForWebURL() {
        let item = DrawerItem.fromDroppedURL(URL(string: "https://example.com/path")!)
        XCTAssertEqual(item.kind, .url)
        XCTAssertEqual(item.url, URL(string: "https://example.com/path"))
        XCTAssertEqual(item.displayName, "example.com")   // host, not the full URL
        XCTAssertNil(item.bookmark)                        // links aren't bookmarked
    }

    func testFromDroppedURLFallsBackToAbsoluteStringWhenNoHost() {
        let item = DrawerItem.fromDroppedURL(URL(string: "mailto:hi@example.com")!)
        XCTAssertEqual(item.kind, .url)
        XCTAssertEqual(item.displayName, "mailto:hi@example.com")
    }

    func testFromDroppedURLMakesFileItemForFileURL() {
        let item = DrawerItem.fromDroppedURL(URL(fileURLWithPath: "/usr/bin", isDirectory: true))
        XCTAssertEqual(item.kind, .folder)                 // a directory on disk
        XCTAssertEqual(item.url?.path, "/usr/bin")
    }

    func testFromLinkDefaultsScheme() {
        let item = DrawerItem.fromLink("example.com")
        XCTAssertEqual(item?.kind, .url)
        XCTAssertEqual(item?.url?.scheme, "https")
    }

    func testAppendDeduplicatingTargetSkipsExistingURL() {
        var items = [DrawerItem(kind: .url, displayName: "Example", url: URL(string: "https://example.com"))]

        items.appendDeduplicatingTarget(DrawerItem(kind: .url, displayName: "Example Again", url: URL(string: "https://example.com")))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.displayName, "Example")
    }

    // MARK: Stable transient ids

    func testStableIDIsDeterministicPerKindAndTarget() {
        let url = URL(fileURLWithPath: "/Users/x/Downloads/report.pdf")
        XCTAssertEqual(DrawerItem.stableID(kind: .file, url: url),
                       DrawerItem.stableID(kind: .file, url: url))
        XCTAssertNotEqual(DrawerItem.stableID(kind: .file, url: url),
                          DrawerItem.stableID(kind: .folder, url: url))
        XCTAssertNotEqual(DrawerItem.stableID(kind: .file, url: url),
                          DrawerItem.stableID(kind: .file, url: URL(fileURLWithPath: "/Users/x/Downloads/other.pdf")))
    }

    func testStableIDNormalizesEquivalentFileURLs() {
        let plain = URL(fileURLWithPath: "/usr/bin")
        let dotted = URL(fileURLWithPath: "/usr/./bin")
        XCTAssertEqual(DrawerItem.stableID(kind: .folder, url: plain),
                       DrawerItem.stableID(kind: .folder, url: dotted))
    }

    func testStableIDWorksForWebURLs() {
        let a = URL(string: "https://example.com/x")!
        XCTAssertEqual(DrawerItem.stableID(kind: .url, url: a), DrawerItem.stableID(kind: .url, url: a))
        XCTAssertNotEqual(DrawerItem.stableID(kind: .url, url: a),
                          DrawerItem.stableID(kind: .url, url: URL(string: "https://example.com/y")!))
    }

    func testTransientFileItemKeepsIdentityAcrossRelistings() {
        let url = URL(fileURLWithPath: "/usr/bin", isDirectory: true)
        XCTAssertEqual(DrawerItem.transientFileItem(url).id, DrawerItem.transientFileItem(url).id)
    }
}
