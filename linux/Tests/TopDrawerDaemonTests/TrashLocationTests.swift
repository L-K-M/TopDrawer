import XCTest
@testable import TopDrawerDaemon

/// Pure tests for the freedesktop Trash location + count — the LP-17 acceptance's "temp
/// trash dirs". Cross-platform: only injected environments and temp directories, no
/// `gio`, so these run on either CI.
final class TrashLocationTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("trashloc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDirectoryHonorsXDGDataHome() {
        let dir = TrashLocation.directory(
            environment: ["XDG_DATA_HOME": "/custom/data"],
            home: URL(fileURLWithPath: "/home/alice"))
        XCTAssertEqual(dir.path, "/custom/data/Trash")
    }

    func testDirectoryFallsBackToLocalShareWhenUnset() {
        let dir = TrashLocation.directory(
            environment: [:], home: URL(fileURLWithPath: "/home/alice"))
        XCTAssertEqual(dir.path, "/home/alice/.local/share/Trash")
    }

    func testDirectoryFallsBackWhenXDGDataHomeIsEmpty() {
        let dir = TrashLocation.directory(
            environment: ["XDG_DATA_HOME": ""], home: URL(fileURLWithPath: "/home/alice"))
        XCTAssertEqual(dir.path, "/home/alice/.local/share/Trash")
    }

    func testDirectoryIgnoresRelativeXDGDataHome() {
        // The XDG spec says a relative $XDG_DATA_HOME must be treated as unset.
        let dir = TrashLocation.directory(
            environment: ["XDG_DATA_HOME": "rel/data"], home: URL(fileURLWithPath: "/home/alice"))
        XCTAssertEqual(dir.path, "/home/alice/.local/share/Trash")
    }

    func testCountIsZeroWhenTrashIsAbsent() {
        XCTAssertEqual(TrashLocation.count(trashDirectory: tempDir), 0)
    }

    func testCountCountsFilesSubdirectoryEntries() throws {
        let files = tempDir.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try "x".write(to: files.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "y".write(to: files.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        // A trashed directory counts as one item, like Finder's Empty Trash.
        try FileManager.default.createDirectory(
            at: files.appendingPathComponent("folder"), withIntermediateDirectories: true)
        XCTAssertEqual(TrashLocation.count(trashDirectory: tempDir), 3)
    }
}
