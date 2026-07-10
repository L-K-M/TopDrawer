import XCTest
@testable import MacDring

final class UpdateDownloaderTests: XCTestCase {

    private enum StubError: Error {
        case unexpectedRequest
    }

    private struct UnexpectedSession: UpdateDownloadSession {
        func downloadAsset(from url: URL) async throws -> (URL, URLResponse) {
            throw StubError.unexpectedRequest
        }
    }

    private struct StubSession: UpdateDownloadSession {
        let tempURL: URL
        let statusCode: Int

        func downloadAsset(from url: URL) async throws -> (URL, URLResponse) {
            let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                           httpVersion: nil, headerFields: nil)!
            return (tempURL, response)
        }
    }

    private func asset(url: String, size: Int) -> GitHubRelease.Asset {
        GitHubRelease.Asset(name: "MacDring.dmg",
                            contentType: "application/x-apple-diskimage",
                            size: size,
                            browserDownloadURL: URL(string: url)!)
    }

    func testRejectsNonHTTPSAssetWithoutStartingDownload() async {
        let downloader = UpdateDownloader(session: UnexpectedSession(), fileManager: .default)

        do {
            _ = try await downloader.downloadToDownloads(asset(url: "http://example.com/MacDring.dmg", size: 1))
            XCTFail("Expected a non-HTTPS URL error")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .nonHTTPSURL(let url) = error else {
                return XCTFail("Unexpected download error: \(error)")
            }
            XCTAssertEqual(url.scheme, "http")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsSizeMismatchAndRemovesTemporaryFile() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UpdateDownloaderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let tempURL = dir.appendingPathComponent("download.tmp")
        let contents = Data("incomplete".utf8)
        try contents.write(to: tempURL)
        let downloader = UpdateDownloader(session: StubSession(tempURL: tempURL, statusCode: 200),
                                          fileManager: fm)

        do {
            _ = try await downloader.downloadToDownloads(
                asset(url: "https://example.com/MacDring.dmg", size: contents.count + 1)
            )
            XCTFail("Expected a file-size mismatch")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .sizeMismatch(let expected, let actual) = error else {
                return XCTFail("Unexpected download error: \(error)")
            }
            XCTAssertEqual(expected, contents.count + 1)
            XCTAssertEqual(actual, contents.count)
        }
        XCTAssertFalse(fm.fileExists(atPath: tempURL.path))
    }

    func testUniqueDestinationAvoidsCollisions() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UpdateDownloaderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let first = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring.dmg", fileManager: fm)
        XCTAssertEqual(first.lastPathComponent, "MacDring.dmg")
        XCTAssertTrue(fm.createFile(atPath: first.path, contents: Data()))

        let second = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring.dmg", fileManager: fm)
        XCTAssertEqual(second.lastPathComponent, "MacDring-1.dmg")
        XCTAssertTrue(fm.createFile(atPath: second.path, contents: Data()))

        let third = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring.dmg", fileManager: fm)
        XCTAssertEqual(third.lastPathComponent, "MacDring-2.dmg")
    }

    func testUniqueDestinationHandlesNameWithoutExtension() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UpdateDownloaderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let first = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring", fileManager: fm)
        XCTAssertEqual(first.lastPathComponent, "MacDring")
        XCTAssertTrue(fm.createFile(atPath: first.path, contents: Data()))

        let second = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring", fileManager: fm)
        XCTAssertEqual(second.lastPathComponent, "MacDring-1")
    }

    func testUniqueDestinationSanitizesPathlikeNames() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UpdateDownloaderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let nested = UpdateDownloader.uniqueDestination(in: dir, fileName: "../../MacDring.dmg", fileManager: fm)
        // Compare paths, not URLs: `deletingLastPathComponent()` always yields a
        // trailing slash that `dir` (built via `appendingPathComponent`) lacks, so a
        // direct URL equality would fail on the trailing-slash difference alone.
        XCTAssertEqual(nested.deletingLastPathComponent().path, dir.path)
        XCTAssertEqual(nested.lastPathComponent, "MacDring.dmg")

        let empty = UpdateDownloader.uniqueDestination(in: dir, fileName: "   ", fileManager: fm)
        XCTAssertEqual(empty.lastPathComponent, "download")

        // An all-separator name collapses to "/" via lastPathComponent, which must
        // still fall back to "download" rather than resolving to the directory itself.
        let slashes = UpdateDownloader.uniqueDestination(in: dir, fileName: "///", fileManager: fm)
        XCTAssertEqual(slashes.deletingLastPathComponent().path, dir.path)
        XCTAssertEqual(slashes.lastPathComponent, "download")
    }
}
