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

    // MARK: Prerelease scan pagination

    #if os(macOS)
    func testPrereleaseScanPagesAndPicksTheHighestVersion() async throws {
        let requestedPages = LockedPageList()
        let session = stubSession { request in
            let page = Int(request.url?.queryParameters["page"] ?? "1") ?? 1
            requestedPages.append(page)
            if page == 1 {
                // A full page, so the scan must continue.
                return (200, self.releasesJSON((0..<GitHubReleaseClient.releasesPerPage).map {
                    (tag: "v1.0.\($0)", draft: false)
                }))
            }
            // An older page carries the highest version — the bug the scan fixes.
            // A draft with an even higher tag must be ignored.
            return (200, self.releasesJSON([
                (tag: "v3.0.0-draft", draft: true),
                (tag: "v2.0.0-beta.1", draft: false),
            ]))
        }
        let client = GitHubReleaseClient(owner: "owner", repo: "repo", session: session)

        let release = try await client.latestRelease(includePrereleases: true)

        XCTAssertEqual(release.tagName, "v2.0.0-beta.1")
        XCTAssertEqual(requestedPages.all, [1, 2])   // stopped on the short page
    }

    func testPrereleaseScanStopsAtThePageBudget() async throws {
        let requestedPages = LockedPageList()
        let session = stubSession { request in
            let page = Int(request.url?.queryParameters["page"] ?? "1") ?? 1
            requestedPages.append(page)
            return (200, self.releasesJSON((0..<GitHubReleaseClient.releasesPerPage).map {
                (tag: "v1.0.\($0)", draft: false)
            }))
        }
        let client = GitHubReleaseClient(owner: "owner", repo: "repo", session: session)

        _ = try await client.latestRelease(includePrereleases: true)

        XCTAssertEqual(requestedPages.all, Array(1...GitHubReleaseClient.maximumPrereleasePages))
    }

    private func releasesJSON(_ entries: [(tag: String, draft: Bool)]) -> Data {
        let json = entries.map { entry in
            "{\"tag_name\":\"\(entry.tag)\",\"html_url\":\"https://example.com/\(entry.tag)\",\"prerelease\":true,\"draft\":\(entry.draft),\"assets\":[]}"
        }.joined(separator: ",")
        return Data("[\(json)]".utf8)
    }

    private func stubSession(_ handler: @escaping (URLRequest) -> (Int, Data)) -> URLSession {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    #endif
}

#if os(macOS)
private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URL {
    var queryParameters: [String: String] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?
            .reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
    }
}

/// Thread-safe page collector: `URLProtocol` delivers on a background queue while
/// the test reads the result after `await`.
private final class LockedPageList {
    private let lock = NSLock()
    private var pages: [Int] = []

    func append(_ page: Int) {
        lock.lock(); pages.append(page); lock.unlock()
    }

    var all: [Int] {
        lock.lock(); defer { lock.unlock() }
        return pages
    }
}
#endif
