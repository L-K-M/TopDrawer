#if os(macOS)
import AppKit
import XCTest
@testable import MacDring

final class NotesDrawerResizeViewTests: XCTestCase {
    func testHandlesPassEditorClicksThroughAndKeepAttachedSideInactive() {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let editor = NSView(frame: container.bounds)
        let overlay = NotesDrawerResizeView(frame: container.bounds)
        overlay.edge = .left
        container.addSubview(editor)
        container.addSubview(overlay)
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(container.hitTest(CGPoint(x: 200, y: 150)) === editor)
        XCTAssertTrue(container.hitTest(CGPoint(x: 2, y: 150)) === editor)
        let freeEdge = container.hitTest(CGPoint(x: 398, y: 150))
        XCTAssertNotNil(freeEdge)
        XCTAssertFalse(freeEdge === editor)
        XCTAssertTrue(freeEdge?.acceptsFirstMouse(for: nil) == true)
        XCTAssertFalse(freeEdge?.needsPanelToBecomeKey == true)

        overlay.isHidden = true
        XCTAssertTrue(container.hitTest(CGPoint(x: 398, y: 150)) === editor)
    }
}
#endif
