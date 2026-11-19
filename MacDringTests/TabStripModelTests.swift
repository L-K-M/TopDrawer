import XCTest
@testable import MacDring

final class TabStripModelTests: XCTestCase {
    private func model(title: String) -> TabStripModel {
        TabStripModel(title: title, colorHex: "#0A84FF", glyph: .symbol("star"), edge: .right,
                      acceptsWebURLDrops: true, acceptsFileDrops: true)
    }

    func testTooltipNamesTheLiveHotkey() {
        let pill = model(title: "Apps")
        XCTAssertEqual(pill.tooltip, "Apps")
        pill.hotkeyLabel = "⌃⌥A"
        XCTAssertEqual(pill.tooltip, "Apps (⌃⌥A)")
        pill.hotkeyLabel = nil
        XCTAssertEqual(pill.tooltip, "Apps", "A refused or removed hotkey is not advertised")
    }

    func testUntitledTabTooltipIsJustTheHotkey() {
        let pill = model(title: "")
        XCTAssertEqual(pill.tooltip, "", "No title and no hotkey: nothing to show")
        pill.hotkeyLabel = "F12"
        XCTAssertEqual(pill.tooltip, "F12")
    }
}
