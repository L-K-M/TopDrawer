#if os(macOS)
import AppKit
import XCTest
@testable import MacDring

final class ItemPreviewControllerTests: XCTestCase {
    private final class DrawerPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func makeParent() -> NSPanel {
        let panel = DrawerPanel(contentRect: NSRect(x: 100, y: 100, width: 320, height: 240),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.orderFrontRegardless()
        return panel
    }

    private final class RecordingOpener: AppLaunching {
        var urls: [URL] = []
        func resolveURL(for item: DrawerItem) -> URL? { item.url }
        func openApplication(at url: URL, reply: @escaping (Error?) -> Void) { reply(nil) }
        func openURL(_ url: URL) -> Bool { urls.append(url); return true }
    }

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
        let parent = makeParent()
        defer { parent.close() }
        parent.level = .popUpMenu
        let preview = ItemPreviewController()
        defer { preview.close() }
        var closes = 0
        preview.onClose = { closes += 1 }
        let wasActive = NSApp.isActive
        XCTAssertTrue(preview.showFile(file, relativeTo: parent))
        XCTAssertEqual(NSApp.isActive, wasActive)
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
        let parent = makeParent()
        defer { parent.close() }
        let preview = ItemPreviewController()
        defer { preview.onClose = nil; preview.close() }
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

    func testExternalOpenReturnsTheTargetAndClosesThePreview() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("Preview fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let parent = makeParent()
        defer { parent.close() }
        let opener = RecordingOpener()
        let preview = ItemPreviewController(opener: opener)
        defer { preview.close() }
        XCTAssertTrue(preview.showFile(file, relativeTo: parent))
        var opened: [URL] = []
        preview.onOpenExternally = { opened.append($0) }
        let panel = try XCTUnwrap(parent.childWindows?.first)
        let button = try XCTUnwrap(panel.contentView?.subviews.flatMap(\.subviews)
            .compactMap { $0 as? NSButton }.first { $0.title == "Open File" })
        button.performClick(nil)
        XCTAssertEqual(opened, [file])
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertTrue(parent.childWindows?.isEmpty ?? true)
    }
}
#endif
