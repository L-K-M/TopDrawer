import XCTest
@testable import MacDring

/// Encodes the global-hotkey conflict resolution at the point it was lifted out of
/// `TabController.registerHotkeyIfNeeded` (LP-11), so the pure move stays a pure move.
final class HotkeyRegistrationPolicyTests: XCTestCase {

    private let a = HotkeySpec(keyCode: 1, carbonModifiers: 0)
    private let b = HotkeySpec(keyCode: 2, carbonModifiers: 0)

    private func decide(spec: HotkeySpec?, usable: Bool = true, existing: HotkeySpec? = nil,
                        cachedFailure: HotkeySpec? = nil, ownedByOtherTab: Bool = false)
        -> HotkeyRegistrationPolicy.Decision {
        HotkeyRegistrationPolicy.decide(spec: spec, usable: usable, existing: existing,
                                        cachedFailure: cachedFailure, ownedByOtherTab: ownedByOtherTab)
    }

    // MARK: No usable spec

    func testNoSpecUnregisters() {
        XCTAssertEqual(decide(spec: nil, usable: false), .unregister)
    }

    func testAnUnusableSpecUnregisters() {
        // A spec that KeyCodes rejects is treated the same as none — drop any registration.
        XCTAssertEqual(decide(spec: a, usable: false), .unregister)
    }

    // MARK: Live registration wins first

    func testAnUnchangedLiveRegistrationIsKept() {
        XCTAssertEqual(decide(spec: a, existing: a), .keepExisting)
    }

    func testAChangedSpecReleasesTheStaleOneThenRegistersWhenFree() {
        XCTAssertEqual(decide(spec: a, existing: b), .releaseStaleThenRegister)
    }

    func testAChangedSpecReleasesTheStaleOneThenDefersWhenOwned() {
        XCTAssertEqual(decide(spec: a, existing: b, ownedByOtherTab: true), .releaseStaleThenDefer)
    }

    func testAChangedSpecIgnoresACachedFailure() {
        // The live-registration branch releases the stale one, which clears the cache, so a
        // cached failure can never apply when a (different) registration exists.
        XCTAssertEqual(decide(spec: a, existing: b, cachedFailure: a), .releaseStaleThenRegister)
    }

    // MARK: No live registration

    func testACachedFailureForTheSameSpecIsLeftFailed() {
        XCTAssertEqual(decide(spec: a, cachedFailure: a), .skipCachedFailure)
    }

    func testAStaleCachedFailureForADifferentSpecDoesNotBlock() {
        // The cache is keyed by tab but compared by spec; a failure recorded for an old
        // spec must not suppress registering the current one.
        XCTAssertEqual(decide(spec: a, cachedFailure: b), .register)
    }

    func testAFreeSpecWithNoRegistrationRegisters() {
        XCTAssertEqual(decide(spec: a), .register)
    }

    func testASpecOwnedByAnotherTabDefersWithoutCaching() {
        XCTAssertEqual(decide(spec: a, ownedByOtherTab: true), .deferToOwner)
    }

    // MARK: Blocked reporting

    func testOnlyTheDeferDecisionsReportBlocked() {
        XCTAssertTrue(HotkeyRegistrationPolicy.isBlocked(.releaseStaleThenDefer))
        XCTAssertTrue(HotkeyRegistrationPolicy.isBlocked(.deferToOwner))
        for decision: HotkeyRegistrationPolicy.Decision in
            [.unregister, .keepExisting, .skipCachedFailure, .releaseStaleThenRegister, .register] {
            XCTAssertFalse(HotkeyRegistrationPolicy.isBlocked(decision), "\(decision) must not block")
        }
    }
}
