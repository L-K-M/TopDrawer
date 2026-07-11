import XCTest
@testable import MacDring

final class GitHubReleaseTests: XCTestCase {

    private func decode(_ json: String) throws -> GitHubRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRelease.self, from: Data(json.utf8))
    }

    func testDecodesLatestReleasePayload() throws {
        let release = try decode("""
        {
          "tag_name": "v1.3.0",
          "name": "Top Drawer 1.3.0",
          "body": "- Fixed a thing\\n- Added another",
          "html_url": "https://github.com/L-K-M/MacDring/releases/tag/v1.3.0",
          "prerelease": false,
          "draft": false,
          "published_at": "2026-05-01T12:00:00Z",
          "assets": [
            {
              "name": "Top Drawer.dmg",
              "content_type": "application/x-apple-diskimage",
              "size": 1048576,
              "browser_download_url": "https://github.com/L-K-M/MacDring/releases/download/v1.3.0/Top%20Drawer.dmg"
            }
          ]
        }
        """)

        XCTAssertEqual(release.tagName, "v1.3.0")
        XCTAssertEqual(SemanticVersion(release.tagName), SemanticVersion("1.3.0"))
        XCTAssertFalse(release.prerelease)
        XCTAssertEqual(release.htmlURL.absoluteString, "https://github.com/L-K-M/MacDring/releases/tag/v1.3.0")
        XCTAssertEqual(release.assets.count, 1)
        XCTAssertEqual(release.assets.first?.name, "Top Drawer.dmg")
        XCTAssertEqual(release.assets.first?.browserDownloadURL.lastPathComponent, "Top Drawer.dmg")
        XCTAssertNotNil(release.publishedAt)
    }

    func testDecodesWithMissingOptionalFields() throws {
        // body/name/published_at absent, no assets — must still decode.
        let release = try decode("""
        {
          "tag_name": "2.0",
          "html_url": "https://github.com/L-K-M/MacDring/releases/tag/2.0",
          "prerelease": true,
          "draft": false,
          "assets": []
        }
        """)
        XCTAssertEqual(release.tagName, "2.0")
        XCTAssertTrue(release.prerelease)
        XCTAssertNil(release.releaseNotes())
        XCTAssertTrue(release.assets.isEmpty)
    }

    func testPreferredAssetPreservesDMGZIPPKGRanking() throws {
        let release = try decode("""
        {
          "tag_name": "1.0", "html_url": "https://e.com", "prerelease": false, "draft": false,
          "assets": [
            {"name":"App.pkg","content_type":"application/vnd.apple.installer+xml","size":1,"browser_download_url":"https://e.com/App.pkg"},
            {"name":"App.zip","content_type":"application/zip","size":1,"browser_download_url":"https://e.com/App.zip"},
            {"name":"App.dmg","content_type":"application/x-apple-diskimage","size":1,"browser_download_url":"https://e.com/App.dmg"}
          ]
        }
        """)
        XCTAssertEqual(release.preferredAsset?.name, "App.dmg")

        let withoutDMG = try decode("""
        {
          "tag_name": "1.0", "html_url": "https://e.com", "prerelease": false, "draft": false,
          "assets": [
            {"name":"App.pkg","content_type":"application/vnd.apple.installer+xml","size":1,"browser_download_url":"https://e.com/App.pkg"},
            {"name":"App.zip","content_type":"application/zip","size":1,"browser_download_url":"https://e.com/App.zip"}
          ]
        }
        """)
        XCTAssertEqual(withoutDMG.preferredAsset?.name, "App.zip")

        let pkgOnly = try decode("""
        {
          "tag_name": "1.0", "html_url": "https://e.com", "prerelease": false, "draft": false,
          "assets": [
            {"name":"notes.txt","content_type":"text/plain","size":1,"browser_download_url":"https://e.com/notes.txt"},
            {"name":"App.pkg","content_type":"application/vnd.apple.installer+xml","size":1,"browser_download_url":"https://e.com/App.pkg"}
          ]
        }
        """)
        XCTAssertEqual(pkgOnly.preferredAsset?.name, "App.pkg")
    }

    func testPreferredAssetNilWhenNoSupportedType() throws {
        let release = try decode("""
        {
          "tag_name": "1.0", "html_url": "https://e.com", "prerelease": false, "draft": false,
          "assets": [
            {"name":"notes.txt","content_type":"text/plain","size":1,"browser_download_url":"https://e.com/notes.txt"}
          ]
        }
        """)
        XCTAssertNil(release.preferredAsset)
    }

    func testPreferredAssetNilWhenNoAssets() throws {
        let release = try decode("""
        { "tag_name": "1.0", "html_url": "https://e.com", "prerelease": false, "draft": false, "assets": [] }
        """)
        XCTAssertNil(release.preferredAsset)
    }

    func testReleaseNotesAreTrimmedAndCapped() throws {
        let long = String(repeating: "x", count: 1000)
        let release = try decode("""
        { "tag_name": "1.0", "html_url": "https://example.com", "prerelease": false, "draft": false, "assets": [], "body": "  \(long)  " }
        """)
        let notes = release.releaseNotes(maxLength: 100)
        XCTAssertEqual(notes?.count, 101)             // 100 chars + the ellipsis
        XCTAssertEqual(notes?.last, "…")
    }
}
