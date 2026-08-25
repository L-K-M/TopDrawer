import XCTest
@testable import MacDring

final class IconNameTests: XCTestCase {

    // MARK: Mapping completeness (the LP-13 acceptance)

    func testEveryCuratedSymbolHasALinuxMapping() {
        let missing = CuratedSymbols.all.filter { IconMap.linux[$0] == nil }
        XCTAssertTrue(missing.isEmpty, "curated picker symbols with no Linux icon mapping: \(missing)")
    }

    func testTheCuratedListHasNoDuplicates() {
        XCTAssertEqual(Set(CuratedSymbols.all).count, CuratedSymbols.all.count,
                       "the symbol picker must not offer the same glyph twice")
    }

    // MARK: Resolution

    func testResolvedOnMacOSReturnsTheStoredSFNameUnchanged() {
        // Storage keeps SF names; macOS rendering is unchanged (no document migration).
        for symbol in ["folder.fill", "square.grid.2x2.fill", "star", "trash"] {
            XCTAssertEqual(IconName(sfSymbol: symbol).resolved(for: .macOS), symbol)
        }
    }

    func testResolvedOnLinuxMapsAKnownSymbolToItsLucideName() {
        XCTAssertEqual(IconName(sfSymbol: "folder.fill").resolved(for: .linux), "folder")
        XCTAssertEqual(IconName(sfSymbol: "trash").resolved(for: .linux), "trash-2")
        XCTAssertEqual(IconName(sfSymbol: "gearshape.fill").resolved(for: .linux), "settings")
    }

    func testAnUnmappedSymbolFallsBackToTheGenericGlyphOnLinux() {
        let unknown = "definitely.not.a.real.symbol.zzz"
        XCTAssertNil(IconMap.linux[unknown])
        XCTAssertFalse(IconName(sfSymbol: unknown).hasLinuxMapping)
        XCTAssertEqual(IconName(sfSymbol: unknown).resolved(for: .linux), IconName.genericLinuxIcon)
    }

    func testHasLinuxMappingReflectsTheMap() {
        XCTAssertTrue(IconName(sfSymbol: "folder.fill").hasLinuxMapping)
        XCTAssertFalse(IconName(sfSymbol: "nope.nope").hasLinuxMapping)
    }
}
