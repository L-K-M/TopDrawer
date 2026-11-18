#if os(macOS)
import AppKit
import XCTest
@testable import MacDring

final class FolderBrowserControllerTests: XCTestCase {
    func testPreferredPopoverEdgeOpensInwardFromTheDrawerEdge() {
        // Non-flipped positioning view (bottom-left origin).
        XCTAssertEqual(FolderBrowserController.preferredPopoverEdge(for: .left, isFlippedView: false), .maxX)
        XCTAssertEqual(FolderBrowserController.preferredPopoverEdge(for: .right, isFlippedView: false), .minX)
        XCTAssertEqual(FolderBrowserController.preferredPopoverEdge(for: .top, isFlippedView: false), .minY)
        XCTAssertEqual(FolderBrowserController.preferredPopoverEdge(for: .bottom, isFlippedView: false), .maxY)
        // Flipped positioning view (top-left origin) swaps the vertical edges.
        XCTAssertEqual(FolderBrowserController.preferredPopoverEdge(for: .left, isFlippedView: true), .maxX)
        XCTAssertEqual(FolderBrowserController.preferredPopoverEdge(for: .right, isFlippedView: true), .minX)
        XCTAssertEqual(FolderBrowserController.preferredPopoverEdge(for: .top, isFlippedView: true), .maxY)
        XCTAssertEqual(FolderBrowserController.preferredPopoverEdge(for: .bottom, isFlippedView: true), .minY)
        // This locks the mapping as a contract; actual inward-opening behavior still
        // needs a manual check per dock edge.
    }

    func testReplacementAndRepeatedCloseNotifyOnlyForTheDismissedSession() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frame = NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY, width: 120, height: 80)
        let parent = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        parent.contentView = view
        parent.orderFrontRegardless()
        defer { parent.orderOut(nil) }
        let browser = FolderBrowserController()
        defer { browser.close() }
        let folder = DrawerItem(kind: .folder, displayName: "Folder", url: directory)
        var closes = 0
        browser.onClose = { closes += 1 }
        let wasActive = NSApp.isActive
        browser.show(folder, relativeTo: view.bounds, of: view,
                     onLaunch: { _ in }, onReveal: { _ in }, onPreview: { _ in })
        XCTAssertTrue(browser.isShown)
        XCTAssertEqual(NSApp.isActive, wasActive)
        browser.show(folder, relativeTo: view.bounds, of: view,
                     onLaunch: { _ in }, onReveal: { _ in }, onPreview: { _ in })
        XCTAssertEqual(closes, 0)
        browser.close()
        browser.close()
        browser.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        XCTAssertFalse(browser.isShown)
        XCTAssertEqual(closes, 1)
    }
}
#endif
