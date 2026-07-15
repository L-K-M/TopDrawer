import XCTest
import AppKit
@testable import MacDring

/// Covers the pure geometry of `ForeignFullScreen` — whether a window's bounds count
/// as fully covering a display (native full-screen) vs. merely large. The live
/// `covers(_ screen:)` reads the window server and is verified by hand.
final class ForeignFullScreenTests: XCTestCase {

    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testExactFillIsFullScreen() {
        XCTAssertTrue(ForeignFullScreen.covers(windowBounds: display, displayBounds: display))
    }

    func testSubPixelDifferenceStillCounts() {
        // Backing-store rounding shouldn't defeat the match.
        let window = CGRect(x: 0.4, y: -0.6, width: 1919.6, height: 1080.7)
        XCTAssertTrue(ForeignFullScreen.covers(windowBounds: window, displayBounds: display))
    }

    func testZoomedWindowLeavingTheMenuBarDoesNotCount() {
        // A green-button-zoomed window stops below the 25 pt menu bar — not full-screen.
        let zoomed = CGRect(x: 0, y: 25, width: 1920, height: 1055)
        XCTAssertFalse(ForeignFullScreen.covers(windowBounds: zoomed, displayBounds: display))
    }

    func testSameSizeOnAnotherDisplayDoesNotCount() {
        // Identical resolution, different origin — a full-screen app on the *other*
        // monitor must not make us think this display is covered.
        let onOtherDisplay = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        XCTAssertFalse(ForeignFullScreen.covers(windowBounds: onOtherDisplay, displayBounds: display))
    }

    func testPartialWindowDoesNotCount() {
        let half = CGRect(x: 0, y: 0, width: 960, height: 1080)
        XCTAssertFalse(ForeignFullScreen.covers(windowBounds: half, displayBounds: display))
    }

    func testDisplayAtNonZeroOriginMatches() {
        // A secondary display sits at a global offset; an exact fill there still counts.
        let secondary = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        XCTAssertTrue(ForeignFullScreen.covers(windowBounds: secondary, displayBounds: secondary))
    }
}
