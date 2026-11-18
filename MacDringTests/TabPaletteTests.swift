import XCTest
@testable import MacDring

final class TabPaletteTests: XCTestCase {
    func testSwatchesAreDistinctValidColors() {
        let hexes = TabPalette.swatches.map(\.hex)
        XCTAssertEqual(Set(hexes).count, hexes.count)
        XCTAssertEqual(Set(TabPalette.swatches.map(\.name)).count, hexes.count)
        for hex in hexes {
            XCTAssertNotNil(NSColor(hex: hex), hex)
            XCTAssertEqual(NSColor(hex: hex)?.hexString, hex, "Swatches use the stored #RRGGBB form")
        }
    }

    func testTheDefaultTabColorIsASwatch() {
        XCTAssertEqual(TabPalette.swatch(matching: Preferences.Default.defaultTabColorHex)?.name, "Blue")
    }

    func testMatchingIgnoresCaseAndAMissingHash() {
        XCTAssertEqual(TabPalette.swatch(matching: "ff453a")?.name, "Red")
        XCTAssertEqual(TabPalette.swatch(matching: " #ff9f0a ")?.name, "Orange")
        XCTAssertNil(TabPalette.swatch(matching: "#123456"), "A custom color selects no swatch")
    }
}
