import XCTest
@testable import MacDring

final class ItemPreviewPolicyTests: XCTestCase {

    // MARK: isWebsite

    func testHTTPAndHTTPSURLsAreWebsites() {
        XCTAssertTrue(ItemPreviewPolicy.isWebsite(URL(string: "https://example.com")!))
        XCTAssertTrue(ItemPreviewPolicy.isWebsite(URL(string: "http://example.com")!))
    }

    func testWebsiteWithPathQueryFragmentAndPort() {
        XCTAssertTrue(ItemPreviewPolicy.isWebsite(
            URL(string: "https://sub.example.com:8443/a/b?q=1&r=2#frag")!))
    }

    func testUppercaseSchemeAndHostStillPass() {
        XCTAssertTrue(ItemPreviewPolicy.isWebsite(URL(string: "HTTPS://EXAMPLE.COM/")!))
    }

    func testUserinfoURLsAreRefused() {
        // Credentials embedded in a URL must never reach the embedded preview.
        XCTAssertFalse(ItemPreviewPolicy.isWebsite(
            URL(string: "https://user:pass@example.com")!))
        XCTAssertFalse(ItemPreviewPolicy.isWebsite(
            URL(string: "https://user@example.com")!))
    }

    func testNonWebSchemesAreRefused() {
        let cases = [
            "file:///etc/passwd",
            "data:text/html,<script>alert(1)</script>",
            "javascript:alert(1)",
            "about:blank",
            "ftp://example.com/file",
            "topdrawer-editor://editor/editor.html",
            "ssh://example.com",
        ]
        for string in cases {
            XCTAssertFalse(ItemPreviewPolicy.isWebsite(URL(string: string)!), string)
        }
    }

    func testHTTPWithoutHostIsRefused() {
        XCTAssertFalse(ItemPreviewPolicy.isWebsite(URL(string: "https:///path")!))
        XCTAssertFalse(ItemPreviewPolicy.isWebsite(URL(string: "http:///")!))
        // On newer platforms this parses to a URL; whether it does or not,
        // it must never be treated as a website.
        if let emptyHost = URL(string: "https://") {
            XCTAssertFalse(ItemPreviewPolicy.isWebsite(emptyHost))
        }
    }

    // MARK: canPreview

    func testFileAndFolderItemsCanPreview() {
        let file = DrawerItem(kind: .file, displayName: "Note",
                              url: URL(fileURLWithPath: "/tmp/note.txt"))
        let folder = DrawerItem(kind: .folder, displayName: "Docs",
                                url: URL(fileURLWithPath: "/tmp/docs", isDirectory: true))
        XCTAssertTrue(ItemPreviewPolicy.canPreview(file))
        XCTAssertTrue(ItemPreviewPolicy.canPreview(folder))
    }

    func testNonFileKindsCannotPreview() {
        let base = URL(fileURLWithPath: "/tmp/thing")
        let items = [
            DrawerItem(kind: .application, displayName: "App", url: base),
            DrawerItem(kind: .trash, displayName: "Trash", url: base),
            DrawerItem(kind: .disk, displayName: "Disk", url: base),
            DrawerItem(kind: .cloud, displayName: "Cloud", url: base),
            DrawerItem(kind: .group, displayName: "Group",
                       children: [DrawerItem(kind: .file, displayName: "Inner", url: base)]),
            DrawerItem(kind: .url, displayName: "Link",
                       url: URL(string: "https://example.com")!),
        ]
        for item in items {
            XCTAssertFalse(ItemPreviewPolicy.canPreview(item), "\(item.kind)")
        }
    }

    func testFileItemWithNonLocalURLCannotPreview() {
        // A corrupt item can carry a remote URL under the .file kind — the local
        // check is on the resolved target, not the kind alone.
        let item = DrawerItem(kind: .file, displayName: "Odd",
                              url: URL(string: "https://example.com/x")!)
        XCTAssertFalse(ItemPreviewPolicy.canPreview(item))
    }

    func testFileItemWithoutAnyTargetCannotPreview() {
        let item = DrawerItem(kind: .file, displayName: "Broken")
        XCTAssertFalse(ItemPreviewPolicy.canPreview(item))
    }
}
