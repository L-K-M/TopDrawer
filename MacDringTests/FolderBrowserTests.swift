import XCTest
@testable import MacDring

final class FolderBrowserTests: XCTestCase {
    func testReadErrorCanBeRetriedWithAValidFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DrawerItem(kind: .folder, displayName: "Folder", url: directory)
        let model = FolderBrowserModel()
        model.load(folder)
        waitUntilLoaded(model)
        XCTAssertNotNil(model.error)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("text".utf8).write(to: directory.appendingPathComponent("Document.txt"))
        model.load(folder)
        waitUntilLoaded(model)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.items.compactMap { $0.url?.lastPathComponent }, ["Document.txt"])
        XCTAssertFalse(model.truncated)
    }

    func testCancellationIgnoresALateListing() {
        let entered = expectation(description: "read started")
        let returned = expectation(description: "read returned")
        let release = DispatchSemaphore(value: 0)
        let entry = DrawerItem(kind: .file, displayName: "Late", slot: 0)
        let model = FolderBrowserModel(listing: { _ in
            entered.fulfill()
            release.wait()
            returned.fulfill()
            return ([entry], false)
        })
        model.load(DrawerItem(kind: .folder, displayName: "Folder"))
        wait(for: [entered], timeout: 5)
        model.cancel()
        release.signal()
        wait(for: [returned], timeout: 5)

        let revived = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !model.items.isEmpty }, object: nil)
        revived.isInverted = true
        wait(for: [revived], timeout: 0.2)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testPopupListingSortsFoldersFirstAndSkipsHiddenFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Z folder"), withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("A.txt"))
        try Data().write(to: directory.appendingPathComponent(".hidden"))
        let listing = try FolderLister.listing(at: directory)
        XCTAssertEqual(listing.items.compactMap { $0.url?.lastPathComponent }, ["Z folder", "A.txt"])
        XCTAssertFalse(listing.truncated)
        XCTAssertTrue(listing.items.allSatisfy { $0.bookmark == nil })
        XCTAssertThrowsError(try FolderLister.listing(at: directory.appendingPathComponent("missing")))
    }

    private func waitUntilLoaded(_ model: FolderBrowserModel) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !model.isLoading }, object: nil)
        wait(for: [ready], timeout: 5)
    }
}
