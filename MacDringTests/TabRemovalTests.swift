import AppKit
import XCTest
@testable import MacDring

final class TabRemovalTests: XCTestCase {
    private func tab(items: [DrawerItem]) -> Tab {
        var tab = Tab(title: "Work", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "test", edge: .left, position: 0.5))
        tab.items = items
        return tab
    }

    func testEmptyTabIsRemovedWithoutAsking() {
        let removes = TabRemoval.confirm(tab(items: [])) { _ in
            XCTFail("An empty tab loses nothing, so it must not prompt")
            return .alertSecondButtonReturn
        }
        XCTAssertTrue(removes)
    }

    func testTabWithItemsAsksAndReturnCannotConfirm() throws {
        let items = [DrawerItem(kind: .file, displayName: "A", slot: 0),
                     DrawerItem(kind: .file, displayName: "B", slot: 1)]
        var shown: NSAlert?
        let removes = TabRemoval.confirm(tab(items: items)) { alert in
            shown = alert
            return .alertSecondButtonReturn
        }

        XCTAssertFalse(removes, "Cancel keeps the tab")
        let alert = try XCTUnwrap(shown)
        XCTAssertEqual(alert.informativeText.contains("2 items"), true)
        XCTAssertEqual(alert.buttons.map(\.title), ["Remove Tab", "Cancel"])
        XCTAssertEqual(alert.buttons.first?.keyEquivalent, "", "Return must not remove the tab")
        XCTAssertEqual(alert.buttons.last?.keyEquivalent, "\u{1b}", "Escape cancels")
        XCTAssertTrue(TabRemoval.confirm(tab(items: items)) { _ in .alertFirstButtonReturn })
    }
}
