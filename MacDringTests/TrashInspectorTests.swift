import XCTest
@testable import MacDring

final class TrashInspectorTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: entryCount (the metadata-only count that also sees loose files)

    func testEntryCountOfEmptyDirectoryIsZero() {
        XCTAssertEqual(TrashInspector.entryCount(of: tempDir), 0)
    }

    func testEntryCountCountsLooseFilesAndSubdirectories() throws {
        let fm = FileManager.default
        try Data().write(to: tempDir.appendingPathComponent("a.txt"))
        try Data().write(to: tempDir.appendingPathComponent("b.txt"))
        try fm.createDirectory(at: tempDir.appendingPathComponent("sub"), withIntermediateDirectories: false)
        // Three entries — crucially the *loose files* count too (the old link-count
        // heuristic saw only the subdirectory and called a files-only Trash "empty").
        XCTAssertEqual(TrashInspector.entryCount(of: tempDir), 3)
    }

    func testEntryCountNilForMissingDirectory() {
        XCTAssertNil(TrashInspector.entryCount(of: tempDir.appendingPathComponent("nope", isDirectory: true)))
    }

    // MARK: isEmpty

    func testIsEmptyReflectsLooseFiles() throws {
        XCTAssertTrue(TrashInspector.isEmpty(tempDir))
        try Data().write(to: tempDir.appendingPathComponent("only-a-file.txt"))
        XCTAssertFalse(TrashInspector.isEmpty(tempDir))   // a single loose file → non-empty
    }

    func testIsEmptyTrueForSubdirectoryOnly() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("sub"), withIntermediateDirectories: false)
        XCTAssertFalse(TrashInspector.isEmpty(tempDir))   // a subfolder also counts
    }

    // MARK: trashDirectories / trashIsEmpty

    func testTrashDirectoriesIncludesHomeTrash() {
        XCTAssertTrue(TrashInspector.trashDirectories().contains { $0.lastPathComponent == ".Trash" })
    }

    func testTrashIsEmptyReturnsABool() {
        // Smoke test: it queries the real Trash (state unknown) but must never throw
        // or prompt — just return a value.
        _ = TrashInspector.trashIsEmpty()
    }
}
