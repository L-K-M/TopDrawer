#if os(macOS)
import AppKit
import XCTest
@testable import MacDring

final class ItemPreviewControllerTests: XCTestCase {
    func testInvalidTargetsDoNotCreateChildPanels() {
        let parent = NSPanel()
        let preview = ItemPreviewController()
        XCTAssertFalse(preview.showWebsite(URL(fileURLWithPath: "/tmp"), relativeTo: parent))
        XCTAssertFalse(preview.showFile(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"), relativeTo: parent))
        XCTAssertTrue(parent.childWindows?.isEmpty ?? true)
    }

    func testClosingAFilePreviewDetachesItAndNotifiesOnce() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("Preview fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let parent = NSPanel()
        parent.level = .popUpMenu
        let preview = ItemPreviewController()
        defer { preview.close() }
        var closes = 0
        preview.onClose = { closes += 1 }
        XCTAssertTrue(preview.showFile(file, relativeTo: parent))
        let child = try XCTUnwrap(parent.childWindows?.first)
        XCTAssertTrue(preview.contains(child))
        XCTAssertTrue(child.styleMask.contains(.nonactivatingPanel))
        XCTAssertGreaterThanOrEqual(child.level.rawValue, parent.level.rawValue)
        preview.close()
        preview.close()
        XCTAssertEqual(closes, 1)
        XCTAssertFalse(preview.contains(child))
        XCTAssertTrue(parent.childWindows?.isEmpty ?? true)
    }

    func testCloseCallbackCanOpenAndCloseAnotherPreview() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("Preview fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let parent = NSPanel()
        let preview = ItemPreviewController()
        defer { preview.close() }
        var closes = 0
        preview.onClose = {
            closes += 1
            guard closes == 1 else { return }
            XCTAssertTrue(preview.showFile(file, relativeTo: parent))
            preview.close()
        }
        XCTAssertTrue(preview.showFile(file, relativeTo: parent))
        preview.close()
        XCTAssertEqual(closes, 2)
        XCTAssertTrue(parent.childWindows?.isEmpty ?? true)
    }
}
#endif
