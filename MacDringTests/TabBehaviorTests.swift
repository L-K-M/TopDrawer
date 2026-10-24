import XCTest
@testable import MacDring

final class TabBehaviorTests: XCTestCase {

    // MARK: resolved(openOnHoverDefault:autoHideDefault:)

    func testResolvedFollowsGlobalWhenNotOverridden() {
        // Stored values are ignored when the tab doesn't override — the globals win.
        let behavior = TabBehavior(openOnHover: true, autoHide: false,
                                   overridesOpenOnHover: false, overridesAutoHide: false)
        let resolved = behavior.resolved(openOnHoverDefault: false, autoHideDefault: true)
        XCTAssertFalse(resolved.openOnHover)
        XCTAssertTrue(resolved.autoHide)
    }

    func testResolvedUsesOwnValueWhenOverridden() {
        let behavior = TabBehavior(openOnHover: true, autoHide: false,
                                   overridesOpenOnHover: true, overridesAutoHide: true)
        let resolved = behavior.resolved(openOnHoverDefault: false, autoHideDefault: true)
        XCTAssertTrue(resolved.openOnHover)    // own value, not the global
        XCTAssertFalse(resolved.autoHide)
    }

    func testResolvedMixesPerField() {
        let behavior = TabBehavior(openOnHover: true, autoHide: true,
                                   overridesOpenOnHover: true, overridesAutoHide: false)
        let resolved = behavior.resolved(openOnHoverDefault: false, autoHideDefault: false)
        XCTAssertTrue(resolved.openOnHover)    // overridden → own
        XCTAssertFalse(resolved.autoHide)      // not overridden → global
    }

    // MARK: Defaults & Codable

    func testOpeningModesPreserveDefaultsAndRoundTrip() throws {
        let legacy = try JSONDecoder().decode(TabBehavior.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.folderOpening, .finder)
        XCTAssertEqual(legacy.websiteOpening, .browser)

        let configured = TabBehavior(folderOpening: .popover, websiteOpening: .popover)
        let data = try JSONEncoder().encode(configured)
        XCTAssertEqual(try JSONDecoder().decode(TabBehavior.self, from: data), configured)
        let malformed = Data(#"{"folderOpening":"future","websiteOpening":123,"keepOpenAfterLaunch":true}"#.utf8)
        let recovered = try JSONDecoder().decode(TabBehavior.self, from: malformed)
        XCTAssertEqual(recovered.folderOpening, .finder)
        XCTAssertEqual(recovered.websiteOpening, .browser)
        XCTAssertTrue(recovered.keepOpenAfterLaunch)
    }

    func testDefaultFollowsGlobal() {
        XCTAssertFalse(TabBehavior.default.overridesOpenOnHover)
        XCTAssertFalse(TabBehavior.default.overridesAutoHide)
    }

    func testCodableRoundTripsOverrides() throws {
        let behavior = TabBehavior(openOnHover: true, autoHide: false, keepOpenAfterLaunch: true,
                                   concealment: .fade, overridesOpenOnHover: true, overridesAutoHide: true)
        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(TabBehavior.self, from: data)
        XCTAssertEqual(behavior, decoded)
    }

    func testDecodingPreOverrideDocumentFollowsGlobal() throws {
        // A document saved before the override flags existed has no override keys.
        let json = #"{"openOnHover":true,"autoHide":false,"keepOpenAfterLaunch":false,"concealment":"never"}"#
        let decoded = try JSONDecoder().decode(TabBehavior.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.overridesOpenOnHover)   // follow global, not "pin the old value"
        XCTAssertFalse(decoded.overridesAutoHide)
        // The stored values survive (latent — used if the user later overrides).
        XCTAssertTrue(decoded.openOnHover)
        XCTAssertFalse(decoded.autoHide)
    }
}
