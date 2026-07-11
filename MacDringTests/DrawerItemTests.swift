import XCTest
@testable import Top Drawer

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

    func testFromLinkDefaultsSchemeAndTrimsInput() {
        let item = DrawerItem.fromLink("  example.com/path  ")
        XCTAssertEqual(item?.kind, .url)
        XCTAssertEqual(item?.url?.absoluteString, "https://example.com/path")
        XCTAssertEqual(item?.displayName, "example.com")
    }

    func testFromLinkTreatsCommonHostPortInputsAsHTTPS() {
        XCTAssertEqual(DrawerItem.fromLink("localhost:3000")?.url?.absoluteString,
                       "https://localhost:3000")
        XCTAssertEqual(DrawerItem.fromLink("example.com:8080")?.url?.absoluteString,
                       "https://example.com:8080")
    }

    func testFromLinkRejectsMalformedSchemesAndHTTPHosts() {
        let malformed = [
            "://example.com",
            "1http://example.com",
            "https://",
            "https:///path",
            "http://?query",
            "https://exa mple.com"
        ]

        for link in malformed {
            XCTAssertNil(DrawerItem.fromLink(link), "Expected \(link) to be invalid")
        }
    }

    func testFromLinkKeepsLegitimateNonHTTPSchemes() {
        XCTAssertEqual(DrawerItem.fromLink("mailto:user@example.com")?.url?.absoluteString,
                       "mailto:user@example.com")
        XCTAssertEqual(DrawerItem.fromLink("ftp://example.com/file")?.url?.absoluteString,
                       "ftp://example.com/file")
        XCTAssertEqual(DrawerItem.fromLink("myapp:foo")?.url?.absoluteString,
                       "myapp:foo")
        XCTAssertEqual(DrawerItem.fromLink("myapp:3000")?.url?.absoluteString,
                       "myapp:3000")
    }

    func testAppendDeduplicatingTargetSkipsExistingURL() {
        var items = [DrawerItem(kind: .url, displayName: "Example", url: URL(string: "https://example.com"))]

        items.appendDeduplicatingTarget(DrawerItem(kind: .url, displayName: "Example Again", url: URL(string: "https://example.com")))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.displayName, "Example")
    }

    func testSlotBoundsMatchForInitializationMutationAndDecoding() throws {
        let maximum = PersistedLayoutBounds.maximumSlotOrOrder
        let cases = [
            (value: -2, expected: -1),
            (value: -1, expected: -1),
            (value: 0, expected: 0),
            (value: maximum, expected: maximum),
            (value: Int.max, expected: -1),
        ]

        for value in cases {
            XCTAssertEqual(DrawerItem(kind: .file, displayName: "Item", slot: value.value).slot,
                           value.expected)

            var mutated = DrawerItem(kind: .file, displayName: "Item")
            mutated.slot = value.value
            XCTAssertEqual(mutated.slot, value.expected)

            let json = #"{"kind":"file","displayName":"Item","slot":\#(value.value)}"#.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(DrawerItem.self, from: json)
            XCTAssertEqual(decoded.slot, value.expected)
        }
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

    func testGroupRoundTripsThroughCodableAndPlainItemOmitsChildren() throws {
        let a = DrawerItem(kind: .application, displayName: "A", url: URL(string: "https://a"), slot: 0)
        let b = DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b"), slot: 1)
        let group = DrawerItem(kind: .group, displayName: "Work", slot: 3, children: [a, b])

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(DrawerItem.self, from: data)
        XCTAssertEqual(decoded, group)
        XCTAssertEqual(decoded.children.count, 2)

        // A plain item's on-disk shape is unchanged — no "children" key.
        let plain = try JSONEncoder().encode(a)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("children"))
    }
}
