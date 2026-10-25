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
}
#endif
