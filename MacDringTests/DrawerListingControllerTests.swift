#if os(macOS)
import AppKit
import XCTest
@testable import MacDring

final class DrawerListingControllerTests: XCTestCase {
    func testOpeningFolderReturnsBeforeItsListingIsRead() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("Document.txt"))

        let suite = "ch.lkmc.MacDring.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let drawer = DrawerWindowController(preferences: Preferences(defaults: defaults))
        defer { drawer.hide(duration: 0) }
        let tab = Tab(title: "Folder", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "test", edge: .left, position: 0.5),
                      kind: .folder, folderURL: directory)
        let resting = EdgeLayout.tabFrame(edge: .left, position: 0.5,
                                          size: CGSize(width: 30, height: 100), in: screen.visibleFrame)

        drawer.show(tab: tab, tabFrame: resting, edge: .left, on: screen, duration: 0)
        XCTAssertTrue(drawer.model.items.isEmpty, "Opening must return before filesystem work completes")

        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            drawer.model.items.first?.url?.lastPathComponent == "Document.txt"
        }, object: nil)
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(drawer.model.folderURL, directory)
    }

    func testRefreshKeepsListingAndPreservesStateWrittenDuringRead() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let entered = expectation(description: "refresh started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let old = DrawerItem(kind: .file, displayName: "Old", url: URL(fileURLWithPath: "/old"))
        let new = DrawerItem(kind: .file, displayName: "New", url: URL(fileURLWithPath: "/new"))
        let folder = URL(fileURLWithPath: "/folder")
        let drawer = try makeDrawer { tab in
            XCTAssertFalse(Thread.isMainThread)
            if tab.title == "Refresh" {
                entered.fulfill()
                release.wait()
                return DrawerListing(items: [new], truncated: false, folderURL: folder)
            }
            return DrawerListing(items: [old], truncated: true, folderURL: folder)
        }
        var tab = folderTab(url: folder)
        try show(tab, in: drawer)
        waitForItems([old], in: drawer)
        tab.title = "Refresh"
        let style = IconStyle(base: .tile, colorHex: "#FF0000", symbol: "star")
        tab.iconStyles = ["/new": style]
        drawer.refresh(tab: tab, tabFrame: restingFrame(on: screen), edge: .left, on: screen)
        wait(for: [entered], timeout: 5)
        XCTAssertEqual(drawer.model.items, [old])
        XCTAssertEqual(drawer.model.folderURL, folder)
        XCTAssertTrue(drawer.model.itemsTruncated)
        XCTAssertTrue(drawer.model.isLoadingListing)
        drawer.model.notes = "New transient state"
        drawer.model.actionError = "An action finished during loading"
        var changedFrames: [CGRect] = []
        drawer.onFrameChanged = { changedFrames.append($0) }

        release.signal()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !drawer.model.isLoadingListing
        }, object: nil)
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(drawer.model.items.first?.id, new.id)
        XCTAssertEqual(drawer.model.items.first?.iconStyle, style)
        XCTAssertFalse(drawer.model.itemsTruncated)
        XCTAssertEqual(drawer.model.notes, "New transient state")
        XCTAssertEqual(drawer.model.actionError, "An action finished during loading")
        XCTAssertEqual(changedFrames.last, drawer.openFrame)
    }

    func testChangingFolderClearsOldTargetsAndClosingDiscardsLateListing() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let entered = expectation(description: "replacement folder read started")
        let returned = expectation(description: "replacement folder read finished")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let old = DrawerItem(kind: .file, displayName: "Old")
        let late = DrawerItem(kind: .file, displayName: "Late")
        let original = URL(fileURLWithPath: "/original")
        let replacement = URL(fileURLWithPath: "/replacement")
        let drawer = try makeDrawer { tab in
            if tab.folderURL == replacement {
                entered.fulfill()
                release.wait()
                returned.fulfill()
                return DrawerListing(items: [late], truncated: false, folderURL: replacement)
            }
            return DrawerListing(items: [old], truncated: true, folderURL: original)
        }
        var tab = folderTab(url: original)
        try show(tab, in: drawer)
        waitForItems([old], in: drawer)
        tab.folderURL = replacement
        drawer.refresh(tab: tab, tabFrame: restingFrame(on: screen), edge: .left, on: screen)
        XCTAssertTrue(drawer.model.items.isEmpty)
        XCTAssertNil(drawer.model.folderURL)
        XCTAssertFalse(drawer.model.itemsTruncated)
        wait(for: [entered], timeout: 5)

        drawer.hide(duration: 0)
        var notes = tab
        notes.kind = .notes
        notes.notes = "Keep this note"
        try show(notes, in: drawer)
        release.signal()
        wait(for: [returned], timeout: 5)
        let revived = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !drawer.model.items.isEmpty || drawer.model.folderURL != nil
        }, object: nil)
        revived.isInverted = true
        wait(for: [revived], timeout: 0.2)
        XCTAssertEqual(drawer.model.notes, "Keep this note")
        XCTAssertFalse(drawer.model.isLoadingListing)
    }

    func testEveryFilesystemTabUsesBackgroundListing() throws {
        let item = DrawerItem(kind: .file, displayName: "Loaded")
        let drawer = try makeDrawer { _ in
            XCTAssertFalse(Thread.isMainThread)
            return DrawerListing(items: [item], truncated: false, folderURL: nil)
        }
        for kind: TabKind in [.folder, .disks, .network, .cloud] {
            var tab = folderTab(url: URL(fileURLWithPath: "/folder"))
            tab.kind = kind
            try show(tab, in: drawer)
            XCTAssertTrue(drawer.model.items.isEmpty)
            XCTAssertTrue(drawer.model.isLoadingListing)
            waitForItems([item], in: drawer)
        }
    }

    private func makeDrawer(read: @escaping (Tab) -> DrawerListing) throws -> DrawerWindowController {
        let suite = "ch.lkmc.MacDring.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let drawer = DrawerWindowController(preferences: Preferences(defaults: defaults), readListing: read)
        addTeardownBlock {
            drawer.hide(duration: 0)
            defaults.removePersistentDomain(forName: suite)
        }
        return drawer
    }

    private func folderTab(url: URL) -> Tab {
        Tab(title: "Folder", colorHex: "#0A84FF",
            anchor: ScreenAnchor(displayUUID: "test", edge: .left, position: 0.5),
            kind: .folder, folderURL: url)
    }

    private func restingFrame(on screen: NSScreen) -> CGRect {
        EdgeLayout.tabFrame(edge: .left, position: 0.5, size: CGSize(width: 30, height: 100), in: screen.visibleFrame)
    }

    private func show(_ tab: Tab, in drawer: DrawerWindowController) throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        drawer.show(tab: tab, tabFrame: restingFrame(on: screen), edge: .left, on: screen, duration: 0)
    }

    private func waitForItems(_ items: [DrawerItem], in drawer: DrawerWindowController) {
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            drawer.model.items == items && !drawer.model.isLoadingListing
        }, object: nil)
        wait(for: [loaded], timeout: 5)
    }
}
#endif
