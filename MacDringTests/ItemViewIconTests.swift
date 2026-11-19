import XCTest
@testable import MacDring

/// Icon-precedence rules for `ItemView`. The asynchronous favicon is the
/// kind-specific default, so it must never replace a user override or the shared
/// store's artwork.
final class ItemViewIconTests: XCTestCase {

    func testFaviconAppliesOnlyToPlainURLItems() {
        var item = DrawerItem(kind: .url, displayName: "Example",
                              url: URL(string: "https://example.com")!)
        XCTAssertTrue(ItemView.shouldApplyFavicon(for: item, hasSharedIcon: false))

        item.customIconBookmark = Data()
        XCTAssertFalse(ItemView.shouldApplyFavicon(for: item, hasSharedIcon: false))
        item.customIconBookmark = nil

        item.iconStyle = IconStyle(base: .tile, colorHex: "#0A84FF", symbol: "globe")
        XCTAssertFalse(ItemView.shouldApplyFavicon(for: item, hasSharedIcon: false))
        item.iconStyle = nil

        XCTAssertFalse(ItemView.shouldApplyFavicon(for: item, hasSharedIcon: true))

        // Any override blocks the favicon, in any combination.
        item.customIconBookmark = Data()
        XCTAssertFalse(ItemView.shouldApplyFavicon(for: item, hasSharedIcon: true))
    }

    func testFaviconDoesNotApplyToNonURLItems() {
        let file = DrawerItem(kind: .file, displayName: "File",
                              url: URL(fileURLWithPath: "/tmp/file"))
        XCTAssertFalse(ItemView.shouldApplyFavicon(for: file, hasSharedIcon: false))

        let app = DrawerItem(kind: .application, displayName: "App",
                             url: URL(fileURLWithPath: "/Applications/App.app"))
        XCTAssertFalse(ItemView.shouldApplyFavicon(for: app, hasSharedIcon: false))
    }
}
