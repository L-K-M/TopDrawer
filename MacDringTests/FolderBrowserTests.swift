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

    func testSubfoldersOpenInPlaceAndBackReturns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sub = directory.appendingPathComponent("Sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("Top.txt"))
        try Data().write(to: sub.appendingPathComponent("Inner.txt"))
        let root = DrawerItem(kind: .folder, displayName: "Root", url: directory)
        let model = FolderBrowserModel()

        model.load(root)
        waitUntilLoaded(model)
        XCTAssertEqual(model.items.compactMap { $0.url?.lastPathComponent }, ["Sub", "Top.txt"])
        XCTAssertFalse(model.canGoBack)

        let file = try XCTUnwrap(model.items.first { $0.kind == .file })
        model.open(file)
        XCTAssertEqual(model.path.count, 1, "Files launch; only folders open in place")

        let folder = try XCTUnwrap(model.items.first { $0.kind == .folder })
        model.open(folder)
        waitUntilLoaded(model)
        XCTAssertEqual(model.current?.url?.lastPathComponent, "Sub")
        XCTAssertTrue(model.canGoBack)
        XCTAssertEqual(model.items.compactMap { $0.url?.lastPathComponent }, ["Inner.txt"])

        model.goBack()
        waitUntilLoaded(model)
        XCTAssertEqual(model.current?.id, root.id)
        XCTAssertFalse(model.canGoBack)
        XCTAssertEqual(model.items.compactMap { $0.url?.lastPathComponent }, ["Sub", "Top.txt"])

        model.load(root)
        XCTAssertEqual(model.path.map(\.id), [root.id], "A new session starts at its own folder")
        waitUntilLoaded(model)
    }

    func testBackShowsTheEnclosingListingAtOnceThenRereadsIt() {
        let root = DrawerItem(kind: .folder, displayName: "Root")
        let sub = DrawerItem(kind: .folder, displayName: "Sub")
        let before = DrawerItem(kind: .file, displayName: "Before")
        let after = DrawerItem(kind: .file, displayName: "After")
        let lock = NSLock()
        var rootReads = 0
        let release = DispatchSemaphore(value: 0)
        let model = FolderBrowserModel { item in
            guard item.id == root.id else { return ([], false) }
            lock.lock(); rootReads += 1; let read = rootReads; lock.unlock()
            if read == 1 { return ([sub, before], false) }
            release.wait()
            return ([sub, after], false)
        }
        model.load(root)
        waitUntilLoaded(model)
        model.open(sub)
        waitUntilLoaded(model)

        model.goBack()
        XCTAssertFalse(model.isLoading, "Back shows the enclosing folder without a spinner")
        XCTAssertEqual(model.items.map(\.id), [sub.id, before.id])
        release.signal()
        let reread = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            model.items.map(\.id) == [sub.id, after.id]
        }, object: nil)
        wait(for: [reread], timeout: 5)
    }

    func testTryAgainRereadsTheFolderBeingShown() {
        let root = DrawerItem(kind: .folder, displayName: "Root")
        let sub = DrawerItem(kind: .folder, displayName: "Sub")
        let lock = NSLock()
        var reads: [UUID] = []
        let model = FolderBrowserModel(listing: { item in
            lock.lock(); reads.append(item.id); lock.unlock()
            return ([], false)
        })
        model.load(root)
        waitUntilLoaded(model)
        model.open(sub)
        waitUntilLoaded(model)
        model.reload()
        waitUntilLoaded(model)
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(reads, [root.id, sub.id, sub.id])
    }

    func testALateListingForTheFolderLeftBehindIsIgnored() {
        let root = DrawerItem(kind: .folder, displayName: "Root")
        let sub = DrawerItem(kind: .folder, displayName: "Sub")
        let entered = expectation(description: "subfolder read started")
        let release = DispatchSemaphore(value: 0)
        let late = DrawerItem(kind: .file, displayName: "Late")
        let model = FolderBrowserModel(listing: { item in
            if item.id == sub.id {
                entered.fulfill()
                release.wait()
                return ([late], false)
            }
            return ([], false)
        })
        model.load(root)
        waitUntilLoaded(model)
        model.open(sub)
        wait(for: [entered], timeout: 5)
        model.goBack()
        release.signal()
        waitUntilLoaded(model)
        let revived = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !model.items.isEmpty }, object: nil)
        revived.isInverted = true
        wait(for: [revived], timeout: 0.3)
        XCTAssertEqual(model.current?.id, root.id)
    }

    private func waitUntilLoaded(_ model: FolderBrowserModel) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !model.isLoading }, object: nil)
        wait(for: [ready], timeout: 5)
    }
}
