import XCTest
@testable import MacDring

final class FolderListerTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdring-folder-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("banana.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("apple.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent(".hidden.txt"))
        try fm.createDirectory(at: dir.appendingPathComponent("ZSub"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func folderTab() -> Tab {
        Tab(title: "F", colorHex: "#0A84FF",
            anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5),
            kind: .folder, folderURL: dir)
    }

    func testListsContentsFoldersFirstSkippingHidden() {
        let items = FolderLister.contents(of: folderTab())
        XCTAssertEqual(items.count, 3)                 // .hidden.txt skipped
        XCTAssertEqual(items[0].kind, .folder)         // directory sorts first
        XCTAssertEqual(items[0].displayName, "ZSub")
        XCTAssertEqual(items[1].kind, .file)
        XCTAssertEqual(items[2].kind, .file)
        XCTAssertTrue(items[1].displayName.hasPrefix("apple"))   // files alphabetical
        XCTAssertTrue(items[2].displayName.hasPrefix("banana"))
        XCTAssertFalse(items.contains { $0.displayName.hasPrefix(".") })
    }

    func testItemsHaveSequentialSlots() {
        let items = FolderLister.contents(of: folderTab())
        XCTAssertEqual(items.map(\.slot), Array(0..<items.count))
    }

    func testItemsAreTransientWithoutBookmarksButStillResolve() throws {
        let items = FolderLister.contents(of: folderTab())
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { $0.bookmark == nil })   // I1: no per-file bookmark
        let sub = try XCTUnwrap(items.first { $0.displayName == "ZSub" })
        XCTAssertEqual(BookmarkResolver.url(for: sub)?.lastPathComponent, "ZSub")  // resolves via url
        XCTAssertFalse(BookmarkResolver.isBroken(sub))
    }

    func testNonFolderTabReturnsEmpty() {
        let tab = Tab(title: "I", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5),
                      kind: .items)
        XCTAssertTrue(FolderLister.contents(of: tab).isEmpty)
    }

    // MARK: Sort + show-hidden

    private func entry(_ name: String, dir: Bool = false, modified: TimeInterval = 0) -> FolderLister.Entry {
        FolderLister.Entry(url: URL(fileURLWithPath: "/d/\(name)"),
                           isDirectory: dir, modified: Date(timeIntervalSince1970: modified))
    }

    func testSortByNameFoldersFirst() {
        let sorted = FolderLister.sorted([
            entry("banana.txt"), entry("Zed", dir: true), entry("apple.txt"), entry("Alpha", dir: true),
        ], by: .name)
        XCTAssertEqual(sorted.map(\.name), ["Alpha", "Zed", "apple.txt", "banana.txt"])
    }

    func testSortByDateModifiedNewestFirst() {
        let sorted = FolderLister.sorted([
            entry("old.txt", modified: 100), entry("new.txt", modified: 300), entry("mid.txt", modified: 200),
        ], by: .dateModified)
        XCTAssertEqual(sorted.map(\.name), ["new.txt", "mid.txt", "old.txt"])
    }

    func testSortByKindGroupsByExtensionThenName() {
        let sorted = FolderLister.sorted([
            entry("b.txt"), entry("a.png"), entry("a.txt"), entry("c.png"),
        ], by: .kind)
        XCTAssertEqual(sorted.map(\.name), ["a.png", "c.png", "a.txt", "b.txt"])
    }

    func testShowsHiddenIncludesDotfilesWhenEnabled() {
        var tab = folderTab()
        tab.folderShowsHidden = true
        let items = FolderLister.contents(of: tab)
        XCTAssertTrue(items.contains { $0.displayName == ".hidden.txt" })
        XCTAssertEqual(items.count, 4)   // ZSub, apple, banana, .hidden
    }
}
