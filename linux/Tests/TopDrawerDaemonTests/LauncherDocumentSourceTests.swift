import XCTest
import Foundation
@testable import TopDrawerDaemon

final class LauncherDocumentSourceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("topdrawerd-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    func testRawJSONReturnsTheFileContentsVerbatim() throws {
        let url = tempDir.appendingPathComponent("launcher.json")
        let json = #"{"version":1,"tabs":[{"id":"A","title":"Apps"}]}"#
        try json.write(to: url, atomically: true, encoding: .utf8)

        let source = LauncherDocumentSource(url: url)
        XCTAssertEqual(source.rawJSON(), json, "the daemon serves the launcher bytes verbatim")
    }

    func testRawJSONFallsBackToEmptyObjectWhenAbsent() {
        let source = LauncherDocumentSource(url: tempDir.appendingPathComponent("nope.json"))
        XCTAssertEqual(source.rawJSON(), "{}", "GetDocument always returns parseable JSON")
    }

    func testDefaultLocationIsTheAppSupportLauncherFile() {
        // Mirrors TabStore.defaultStoreURL: <app-support>/MacDring/launcher.json, where
        // app-support resolves to $XDG_DATA_HOME on Linux.
        let source = LauncherDocumentSource.default()
        XCTAssertTrue(source.url.path.hasSuffix("/MacDring/launcher.json"), source.url.path)
    }

    func testModificationDateTracksTheFile() throws {
        let url = tempDir.appendingPathComponent("launcher.json")
        let source = LauncherDocumentSource(url: url)
        XCTAssertNil(source.modificationDate(), "no file yet")

        try "{}".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNotNil(source.modificationDate(), "present once written")
    }
}
