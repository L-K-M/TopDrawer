import XCTest
@testable import MacDring

final class SemanticVersionTests: XCTestCase {

    func testParsesAndStripsLeadingV() {
        XCTAssertEqual(SemanticVersion("v1.2.3")?.components, [1, 2, 3])
        XCTAssertEqual(SemanticVersion("1.2.3")?.components, [1, 2, 3])
        XCTAssertEqual(SemanticVersion("  V2.0  ")?.components, [2, 0])
    }

    func testRejectsGarbage() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion("1.x.3"))
        XCTAssertNil(SemanticVersion("v"))
    }

    func testComparisonIsNumericNotLexical() {
        XCTAssertTrue(SemanticVersion("1.10.0")! > SemanticVersion("1.9.0")!)   // 10 > 9
        XCTAssertTrue(SemanticVersion("2.0.0")! > SemanticVersion("1.999.0")!)
    }

    func testZeroPaddingEquivalence() {
        XCTAssertEqual(SemanticVersion("1.2"), SemanticVersion("1.2.0"))
        XCTAssertFalse(SemanticVersion("1.2")! < SemanticVersion("1.2.0")!)
        XCTAssertFalse(SemanticVersion("1.2.0")! < SemanticVersion("1.2")!)
    }

    func testPrereleaseSortsBelowFinal() {
        XCTAssertTrue(SemanticVersion("1.2.0-beta.1")! < SemanticVersion("1.2.0")!)
        XCTAssertTrue(SemanticVersion("1.2.0")! > SemanticVersion("1.2.0-rc.1")!)
        XCTAssertTrue(SemanticVersion("1.2.0-beta")! > SemanticVersion("1.1.9")!)   // numbers win first
    }

    func testPrereleaseIdentifiersCompareNumerically() {
        // SemVer §11: numeric identifiers compare numerically, not lexically.
        XCTAssertTrue(SemanticVersion("1.4.0-beta.9")! < SemanticVersion("1.4.0-beta.10")!)
        XCTAssertTrue(SemanticVersion("1.4.0-beta.2")! < SemanticVersion("1.4.0-beta.10")!)
        XCTAssertTrue(SemanticVersion("1.0.0-rc.1")! < SemanticVersion("1.0.0-rc.10")!)
    }

    func testPrereleaseAlphanumericOrdering() {
        XCTAssertTrue(SemanticVersion("1.0.0-alpha")! < SemanticVersion("1.0.0-beta")!)
        XCTAssertTrue(SemanticVersion("1.0.0-alpha.beta")! < SemanticVersion("1.0.0-beta.2")!)
        // Numeric identifiers rank below alphanumeric ones.
        XCTAssertTrue(SemanticVersion("1.0.0-alpha.1")! < SemanticVersion("1.0.0-alpha.beta")!)
    }

    func testShorterPrereleaseIsOlderWhenPrefixesMatch() {
        XCTAssertTrue(SemanticVersion("1.0.0-alpha")! < SemanticVersion("1.0.0-alpha.1")!)
        XCTAssertTrue(SemanticVersion("1.0.0-beta")! < SemanticVersion("1.0.0-beta.0")!)
    }

    func testEqualPrereleasesAreEqual() {
        XCTAssertEqual(SemanticVersion("1.0.0-beta.2"), SemanticVersion("1.0.0-beta.2"))
        XCTAssertFalse(SemanticVersion("1.0.0-beta.2")! < SemanticVersion("1.0.0-beta.2")!)
    }

    func testNewerThanCurrentDetection() {
        let current = SemanticVersion("1.0")!
        XCTAssertTrue(SemanticVersion("1.0.1")! > current)
        XCTAssertTrue(SemanticVersion("1.1")! > current)
        XCTAssertFalse(SemanticVersion("1.0")! > current)
        XCTAssertFalse(SemanticVersion("0.9")! > current)
    }

    func testIgnoresBuildMetadata() {
        XCTAssertEqual(SemanticVersion("1.2.3+build.99"), SemanticVersion("1.2.3"))
    }
}
