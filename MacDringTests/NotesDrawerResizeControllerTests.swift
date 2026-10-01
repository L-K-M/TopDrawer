#if os(macOS)
import AppKit
import XCTest
@testable import MacDring

final class NotesDrawerResizeControllerTests: XCTestCase {
    func testGeometryRefreshAfterNoNetResizeRetainsOriginalPreference() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let suite = "ch.lkmc.MacDring.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let visible = screen.visibleFrame
        let originalSize = try XCTUnwrap(NotesDrawerSize(width: 320, height: Double(visible.height * 2)))
        let tab = Tab(title: "Scratch", colorHex: "#FFD60A",
                      anchor: ScreenAnchor(displayUUID: "test", edge: .left, position: 0.25),
                      kind: .notes, notes: "Stored text", notesSize: originalSize)
        let drawer = DrawerWindowController(preferences: Preferences(defaults: defaults))
        defer { drawer.hide(duration: 0) }
        let resting = EdgeLayout.tabFrame(edge: .left, position: tab.anchor.position,
                                           size: CGSize(width: 30, height: 100), in: visible)
        drawer.show(tab: tab, tabFrame: resting, edge: .left, on: screen, duration: 0)
        let overlay = try XCTUnwrap(drawer.window.contentView?.subviews.compactMap { $0 as? NotesDrawerResizeView }.first)
        var writes = 0
        drawer.onNotesSizeChanged = { _, _ in writes += 1 }
        drawer.model.notes = "Live edit"

        // The displayed height is clamped, so a temporary resize changes its alignment.
        let mouse = CGPoint(x: drawer.openFrame.maxX, y: drawer.openFrame.midY)
        overlay.onEvent?(.began(.right, mouse))
        overlay.onEvent?(.dragged(CGPoint(x: mouse.x + 40, y: mouse.y)))
        overlay.onEvent?(.dragged(mouse))
        XCTAssertTrue(drawer.isResizing)

        var movedTab = tab
        movedTab.anchor.edge = .top
        movedTab.anchor.position = 0.5
        let topTab = EdgeLayout.tabFrame(edge: .top, position: movedTab.anchor.position,
                                          size: CGSize(width: 100, height: 30), in: visible)
        drawer.refresh(tab: movedTab, tabFrame: topTab, edge: .top, on: screen)

        let maximum = NotesDrawerResize.maximumSize(edge: .top, tabFrame: topTab, in: visible)
        let expected = EdgeLayout.openDrawerFrame(edge: .top, tabFrame: topTab,
                                                   contentSize: CGSize(width: 320, height: maximum.height),
                                                   tabPosition: originalSize.tabPosition, in: visible)
        XCTAssertEqual(drawer.openFrame.minX, expected.minX, accuracy: 0.001)
        XCTAssertEqual(drawer.openFrame.minY, expected.minY, accuracy: 0.001)
        XCTAssertEqual(drawer.openFrame.size, expected.size)
        XCTAssertFalse(drawer.isResizing)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(drawer.model.notes, "Live edit")
    }
}
#endif
