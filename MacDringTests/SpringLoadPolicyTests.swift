import XCTest
@testable import MacDring

/// Encodes the spring-load / drag-peek behavior at the point it was lifted out of
/// `TabController` (LP-11), so the pure move stays a pure move.
final class SpringLoadPolicyTests: XCTestCase {

    // MARK: Dwell timings & margins (pin the extracted constants)

    func testDwellTimingsAndMarginsAreUnchanged() {
        XCTAssertEqual(SpringLoadPolicy.springOpenDelay, 0.5, accuracy: 1e-9)
        XCTAssertEqual(SpringLoadPolicy.reConcealDelay, 0.45, accuracy: 1e-9)
        XCTAssertEqual(SpringLoadPolicy.revealSlop, 6, accuracy: 1e-9)
        XCTAssertEqual(SpringLoadPolicy.peekSlop, 60, accuracy: 1e-9)
    }

    func testSlopIsTheWidePeekMarginOnlyWhileAFileIsDragged() {
        XCTAssertEqual(SpringLoadPolicy.slop(peeking: true), SpringLoadPolicy.peekSlop)
        XCTAssertEqual(SpringLoadPolicy.slop(peeking: false), SpringLoadPolicy.revealSlop)
    }

    // MARK: Spring-open

    func testSpringOpenCancelsWhenTheDragLeaves() {
        XCTAssertEqual(SpringLoadPolicy.springAction(isTargeted: false, isOpen: false), .cancel)
        XCTAssertEqual(SpringLoadPolicy.springAction(isTargeted: false, isOpen: true), .cancel)
    }

    func testSpringOpenDoesNothingWhenTheDrawerIsAlreadyOpen() {
        XCTAssertEqual(SpringLoadPolicy.springAction(isTargeted: true, isOpen: true), .alreadyOpen)
    }

    func testSpringOpenArmsWhenHoveringAClosedTabWithADrag() {
        XCTAssertEqual(SpringLoadPolicy.springAction(isTargeted: true, isOpen: false), .scheduleOpen)
    }

    // MARK: Reveal decision

    /// Three well-separated hover zones on the right edge.
    private func zones() -> [CGRect] {
        [CGRect(x: 1400, y: 100, width: 40, height: 44),
         CGRect(x: 1400, y: 400, width: 40, height: 44),
         CGRect(x: 1400, y: 700, width: 40, height: 44)]
    }

    func testIndependentModeRevealsOnlyTheHoveredTab() {
        let reveals = SpringLoadPolicy.reveals(zones: zones(), mouse: CGPoint(x: 1420, y: 420),
                                               revealAllTogether: false)
        XCTAssertEqual(reveals, [false, true, false], "only the middle zone contains the cursor")
    }

    func testRevealAllTogetherRevealsEveryTabWhenAnyZoneIsHovered() {
        let reveals = SpringLoadPolicy.reveals(zones: zones(), mouse: CGPoint(x: 1420, y: 420),
                                               revealAllTogether: true)
        XCTAssertEqual(reveals, [true, true, true], "hovering any grouped tab reveals them all")
    }

    func testIndependentModeRevealsNothingWhenNoZoneIsHovered() {
        // The fourth cell of the revealAllTogether × cursor-over-a-zone truth table: with
        // the cursor over no zone, independent mode conceals everything (not all-revealed).
        let reveals = SpringLoadPolicy.reveals(zones: zones(), mouse: CGPoint(x: 10, y: 10),
                                               revealAllTogether: false)
        XCTAssertEqual(reveals, [false, false, false])
    }

    func testRevealAllTogetherRevealsNothingWhenNoZoneIsHovered() {
        let reveals = SpringLoadPolicy.reveals(zones: zones(), mouse: CGPoint(x: 10, y: 10),
                                               revealAllTogether: true)
        XCTAssertEqual(reveals, [false, false, false])
    }

    // MARK: Reveal transition

    func testRevealTransitionRevealsWhenTheDecisionIsToReveal() {
        for concealed in [true, false] {
            for animated in [true, false] {
                XCTAssertEqual(SpringLoadPolicy.revealTransition(reveal: true, isConcealed: concealed,
                                                                 animated: animated), .reveal)
            }
        }
    }

    func testRevealTransitionKeepsAnAlreadyConcealedTabHidden() {
        XCTAssertEqual(SpringLoadPolicy.revealTransition(reveal: false, isConcealed: true, animated: true),
                       .keepConcealed)
        XCTAssertEqual(SpringLoadPolicy.revealTransition(reveal: false, isConcealed: true, animated: false),
                       .keepConcealed)
    }

    func testRevealTransitionSchedulesDelayedReConcealOnlyOnAnimatedPasses() {
        XCTAssertEqual(SpringLoadPolicy.revealTransition(reveal: false, isConcealed: false, animated: true),
                       .scheduleReConceal)
    }

    func testRevealTransitionSnapsHiddenAtOnceOnInstantPasses() {
        XCTAssertEqual(SpringLoadPolicy.revealTransition(reveal: false, isConcealed: false, animated: false),
                       .concealNow)
    }
}
