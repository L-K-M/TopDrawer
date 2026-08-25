import XCTest
#if canImport(AppKit)
import AppKit
#endif
@testable import MacDring

final class PreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.macdring.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsWhenEmpty() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.drawerTranslucency, Preferences.Default.drawerTranslucency)
        XCTAssertEqual(prefs.iconSize, Preferences.Default.iconSize)
        XCTAssertEqual(prefs.tabThickness, Preferences.Default.tabThickness)
        XCTAssertEqual(prefs.disconnectPolicy, .park)
        XCTAssertTrue(prefs.launchOnSingleClick)
        XCTAssertEqual(prefs.newTabConcealment, .never)
        XCTAssertFalse(prefs.revealAllConcealedTogether)
    }

    func testRevealAllConcealedTogetherRoundTrips() {
        let prefs = Preferences(defaults: defaults)
        prefs.revealAllConcealedTogether = true
        XCTAssertTrue(Preferences(defaults: defaults).revealAllConcealedTogether)
    }

    func testFreshDirectScanDefaultsOffAndRoundTrips() {
        // Off by default: the Fresh pipeline must stay Spotlight-only — and so
        // prompt-free — until the user explicitly opts into the direct folder
        // check (FB1 / PR #61).
        let prefs = Preferences(defaults: defaults)
        XCTAssertFalse(prefs.freshDirectScan)

        prefs.freshDirectScan = true
        XCTAssertTrue(Preferences(defaults: defaults).freshDirectScan)
    }

    func testDrawerTranslucencyBackingOpacityRunsTranslucentToSolid() {
        XCTAssertEqual(DrawerTranslucency.translucent.backingOpacity, 0)
        XCTAssertLessThan(DrawerTranslucency.translucent.backingOpacity, DrawerTranslucency.frosted.backingOpacity)
        XCTAssertLessThan(DrawerTranslucency.frosted.backingOpacity, DrawerTranslucency.solid.backingOpacity)
        XCTAssertEqual(DrawerTranslucency.solid.backingOpacity, 1)
    }

    func testNewTabConcealmentRoundTripAndSeedsBehavior() {
        let prefs = Preferences(defaults: defaults)
        prefs.newTabConcealment = .fade
        XCTAssertEqual(prefs.newTabBehavior.concealment, .fade)   // seeds new tabs

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.newTabConcealment, .fade)
    }

    func testEnumRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.drawerTranslucency = .solid
        prefs.disconnectPolicy = .moveToMain
        prefs.tabWindowLevel = .normal

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.drawerTranslucency, .solid)
        XCTAssertEqual(reloaded.disconnectPolicy, .moveToMain)
        XCTAssertEqual(reloaded.tabWindowLevel, .normal)
    }

    #if !canImport(ServiceManagement)
    // Linux has no SMAppService, so launchAtLogin is a plain persisted preference with
    // no system side effect; it must still round-trip like every other setting.
    func testLaunchAtLoginRoundTripsOnLinux() {
        let prefs = Preferences(defaults: defaults)
        prefs.launchAtLogin = true
        XCTAssertTrue(Preferences(defaults: defaults).launchAtLogin)
        prefs.launchAtLogin = false
        XCTAssertFalse(Preferences(defaults: defaults).launchAtLogin)
    }

    // A refresh has no authoritative system state to read on Linux
    // (systemLaunchAtLoginEnabled() is nil), so it must leave the stored value alone
    // rather than clobber the preference the round-trip above relies on.
    func testRefreshLaunchAtLoginDoesNotClobberOnLinux() {
        let prefs = Preferences(defaults: defaults)
        prefs.launchAtLogin = true
        prefs.refreshLaunchAtLoginStatus()
        XCTAssertTrue(prefs.launchAtLogin)
        XCTAssertTrue(Preferences(defaults: defaults).launchAtLogin)
    }
    #endif

    #if canImport(AppKit)
    // `drawerWindowLevel` returns an `NSWindow.Level` (AppKit), so this pins macOS
    // window-layering behaviour only; there is no Linux equivalent to assert.
    func testDrawerWindowLevelTracksTabWindowLevel() {
        XCTAssertEqual(TabWindowLevel.floating.drawerWindowLevel, .popUpMenu)
        XCTAssertGreaterThan(TabWindowLevel.normal.drawerWindowLevel.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertLessThan(TabWindowLevel.normal.drawerWindowLevel.rawValue, NSWindow.Level.floating.rawValue)
    }
    #endif

    func testNumericRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.iconSize = 96
        prefs.gridColumns = 6
        prefs.cornerRadius = 20
        prefs.tabThickness = 50
        prefs.fadedOpacity = 0.35

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.iconSize, 96)
        XCTAssertEqual(reloaded.gridColumns, 6)
        XCTAssertEqual(reloaded.cornerRadius, 20)
        XCTAssertEqual(reloaded.tabThickness, 50)
        XCTAssertEqual(reloaded.fadedOpacity, 0.35)
    }

    func testFadedOpacityDefaultAndClamp() {
        XCTAssertEqual(Preferences(defaults: defaults).fadedOpacity, Preferences.Default.fadedOpacity)

        defaults.set(5.0, forKey: "fadedOpacity")
        XCTAssertLessThanOrEqual(Preferences(defaults: defaults).fadedOpacity, 0.9)
        defaults.set(0.0, forKey: "fadedOpacity")
        XCTAssertGreaterThanOrEqual(Preferences(defaults: defaults).fadedOpacity, 0.05)
    }

    func testOutOfRangeValuesAreClamped() {
        defaults.set(100_000.0, forKey: "iconSize")
        defaults.set(99.0, forKey: "gridColumns")
        defaults.set(-5.0, forKey: "cornerRadius")
        defaults.set(1_000.0, forKey: "tabThickness")
        defaults.set(-10.0, forKey: "animationMs")

        let prefs = Preferences(defaults: defaults)
        XCTAssertLessThanOrEqual(prefs.iconSize, 128)
        XCTAssertLessThanOrEqual(prefs.gridColumns, 12)
        XCTAssertGreaterThanOrEqual(prefs.cornerRadius, 0)
        XCTAssertLessThanOrEqual(prefs.tabThickness, 64)
        XCTAssertGreaterThanOrEqual(prefs.animationMs, 0)
    }

    func testNonFiniteValueFallsBackToDefault() {
        defaults.set(Double.nan, forKey: "iconSize")
        XCTAssertEqual(Preferences(defaults: defaults).iconSize, Preferences.Default.iconSize)
    }

    func testInvalidStoredColorFallsBackToDefault() {
        defaults.set("not-a-color", forKey: "defaultTabColorHex")
        XCTAssertEqual(Preferences(defaults: defaults).defaultTabColorHex, Preferences.Default.defaultTabColorHex)
    }

    #if canImport(AppKit)
    // Exercises the AppKit `NSColor(hex:)` parser directly (ColorHex.swift); the Linux
    // build validates hex strings through `Preferences`'s own pure checker instead
    // (see `testInvalidStoredColorFallsBackToDefault`).
    func testColorHexRoundTrip() {
        XCTAssertEqual(NSColor(hex: "#0A84FF")?.hexString, "#0A84FF")
        XCTAssertNil(NSColor(hex: "nothex"))
    }
    #endif

    // MARK: Login item seam (LP-13)

    /// A fake `LoginItemManaging` that records `setEnabled` calls and can be told to fail,
    /// so the launch-at-login flow is testable without a real `SMAppService`.
    private final class FakeLoginItem: LoginItemManaging {
        var enabled: Bool?
        var failWith: String?
        private(set) var setCalls: [Bool] = []

        init(enabled: Bool? = nil, failWith: String? = nil) {
            self.enabled = enabled
            self.failWith = failWith
        }

        func isEnabled() -> Bool? { enabled }

        func setEnabled(_ enabled: Bool) -> String? {
            setCalls.append(enabled)
            if let failWith { return failWith }
            self.enabled = enabled   // success reflects the new state
            return nil
        }
    }

    func testInitReadsTheAuthoritativeLoginState() {
        // A system that reports "enabled" overrides the stored default.
        let prefs = Preferences(defaults: defaults, loginItem: FakeLoginItem(enabled: true))
        XCTAssertTrue(prefs.launchAtLogin)
    }

    func testTogglingLaunchAtLoginAppliesThroughTheSeamAndPersists() {
        let login = FakeLoginItem(enabled: false)
        let prefs = Preferences(defaults: defaults, loginItem: login)
        XCTAssertFalse(prefs.launchAtLogin)

        prefs.launchAtLogin = true
        XCTAssertEqual(login.setCalls, [true], "the seam applies the change")
        XCTAssertNil(prefs.launchAtLoginError)
        XCTAssertTrue(prefs.launchAtLogin)
        XCTAssertTrue(defaults.bool(forKey: "launchAtLogin"), "and it round-trips to defaults")
    }

    func testAFailedLoginItemChangeSurfacesTheErrorAndRollsBack() {
        let login = FakeLoginItem(enabled: false, failWith: "denied")
        let prefs = Preferences(defaults: defaults, loginItem: login)

        prefs.launchAtLogin = true
        XCTAssertEqual(login.setCalls, [true])
        XCTAssertEqual(prefs.launchAtLoginError, "denied")
        // The system state didn't change, so the toggle rolls back to the actual state.
        XCTAssertFalse(prefs.launchAtLogin)
        XCTAssertFalse(defaults.bool(forKey: "launchAtLogin"))
    }

    func testRefreshPicksUpAnExternalLoginStateChange() {
        let login = FakeLoginItem(enabled: false)
        let prefs = Preferences(defaults: defaults, loginItem: login)
        XCTAssertFalse(prefs.launchAtLogin)

        login.enabled = true   // changed outside the app (System Settings)
        prefs.refreshLaunchAtLoginStatus()
        XCTAssertTrue(prefs.launchAtLogin)
    }

    func testInitFallsBackToStoredLoginStateWhenSeamReportsNothing() {
        // When the seam has no authoritative state to report (Linux's no-op, or a
        // platform where the status is unknown), the stored preference is what wins.
        defaults.set(true, forKey: "launchAtLogin")
        let prefs = Preferences(defaults: defaults, loginItem: FakeLoginItem(enabled: nil))
        XCTAssertTrue(prefs.launchAtLogin, "stored preference wins when the seam reports nil")

        // With nothing stored either, init must default to false rather than guess —
        // this pins the trailing `?? false` (the fresh-install / Linux no-op default).
        defaults.removeObject(forKey: "launchAtLogin")
        XCTAssertFalse(
            Preferences(defaults: defaults, loginItem: FakeLoginItem(enabled: nil)).launchAtLogin,
            "no seam state and no stored value defaults to false")
    }
}
