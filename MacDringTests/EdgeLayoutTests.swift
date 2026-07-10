import XCTest
@testable import MacDring

final class EdgeLayoutTests: XCTestCase {

    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let pill = CGSize(width: 40, height: 120)

    // MARK: Tab placement

    func testRightEdgeCenteredTab() {
        let frame = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: visible)
        XCTAssertEqual(frame.maxX, visible.maxX, accuracy: 0.001)          // flush to right
        XCTAssertEqual(frame.midY, 400, accuracy: 0.001)                   // vertically centered
        XCTAssertEqual(frame.width, 40, accuracy: 0.001)
    }

    func testLeftEdgeIsFlushLeft() {
        let frame = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: visible)
        XCTAssertEqual(frame.minX, visible.minX, accuracy: 0.001)
    }

    func testBottomEdgeIsFlushBottom() {
        let frame = EdgeLayout.tabFrame(edge: .bottom, position: 0.5, size: pill, in: visible)
        XCTAssertEqual(frame.minY, visible.minY, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 500, accuracy: 0.001)
    }

    func testTopEdgeIsFlushTop() {
        let frame = EdgeLayout.tabFrame(edge: .top, position: 0.5, size: pill, in: visible)
        XCTAssertEqual(frame.maxY, visible.maxY, accuracy: 0.001)
    }

    func testVerticalPositionZeroIsTopAndClampedOnScreen() {
        // position 0 = top; the pill is pinned fully on-screen at the top.
        let frame = EdgeLayout.tabFrame(edge: .right, position: 0, size: pill, in: visible)
        XCTAssertEqual(frame.maxY, visible.maxY, accuracy: 0.001)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY + 0.001)
    }

    func testVerticalPositionOneIsBottomAndClampedOnScreen() {
        let frame = EdgeLayout.tabFrame(edge: .right, position: 1, size: pill, in: visible)
        XCTAssertEqual(frame.minY, visible.minY, accuracy: 0.001)
    }

    func testPositionIsClampedIntoRange() {
        let high = EdgeLayout.tabFrame(edge: .right, position: 5, size: pill, in: visible)
        let one = EdgeLayout.tabFrame(edge: .right, position: 1, size: pill, in: visible)
        XCTAssertEqual(high, one)
    }

    // MARK: Auto-hide (off-edge) frame

    func testHiddenTabLeavesOnlyASliverOnScreen() {
        let reveal: CGFloat = 3
        for edge in Edge.allCases {
            let resting = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let hidden = EdgeLayout.hiddenTabFrame(edge: edge, restingTabFrame: resting, in: visible, reveal: reveal)

            // Size is unchanged — the pill just slides out past the edge.
            XCTAssertEqual(hidden.size.width, resting.size.width, accuracy: 0.001)
            XCTAssertEqual(hidden.size.height, resting.size.height, accuracy: 0.001)

            // Exactly `reveal` points remain inside the screen on the tab's edge.
            switch edge {
            case .left:   XCTAssertEqual(hidden.maxX, visible.minX + reveal, accuracy: 0.001)
            case .right:  XCTAssertEqual(hidden.minX, visible.maxX - reveal, accuracy: 0.001)
            case .top:    XCTAssertEqual(hidden.minY, visible.maxY - reveal, accuracy: 0.001)
            case .bottom: XCTAssertEqual(hidden.maxY, visible.minY + reveal, accuracy: 0.001)
            }
        }
    }

    func testHiddenTabKeepsAlongEdgePosition() {
        // The flush-to-edge axis moves; the along-edge axis stays put.
        let vertical = EdgeLayout.tabFrame(edge: .right, position: 0.3, size: pill, in: visible)
        XCTAssertEqual(EdgeLayout.hiddenTabFrame(edge: .right, restingTabFrame: vertical, in: visible).minY,
                       vertical.minY, accuracy: 0.001)

        let horizontal = EdgeLayout.tabFrame(edge: .bottom, position: 0.7, size: CGSize(width: 120, height: 40), in: visible)
        XCTAssertEqual(EdgeLayout.hiddenTabFrame(edge: .bottom, restingTabFrame: horizontal, in: visible).minX,
                       horizontal.minX, accuracy: 0.001)
    }

    func testAutoHideSpillIsDetectedOnAnEdgeSharedWithAnotherDisplay() {
        // A right display whose left edge butts against a left display: hiding a
        // left-edge tab there would slide onto the neighbor.
        let rightVisible = CGRect(x: 1000, y: 0, width: 1000, height: 760)
        let leftFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let resting = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: rightVisible)

        XCTAssertTrue(EdgeLayout.hiddenFrameSpillsOntoOtherScreens(
            edge: .left, restingTabFrame: resting, screenVisibleFrame: rightVisible, otherScreenFrames: [leftFrame]))
    }

    func testAutoHideDoesNotSpillOnAnOuterEdge() {
        // The right display's *right* edge is the outer edge of the desktop.
        let rightVisible = CGRect(x: 1000, y: 0, width: 1000, height: 760)
        let leftFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let resting = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: rightVisible)

        XCTAssertFalse(EdgeLayout.hiddenFrameSpillsOntoOtherScreens(
            edge: .right, restingTabFrame: resting, screenVisibleFrame: rightVisible, otherScreenFrames: [leftFrame]))
    }

    func testAutoHideDoesNotSpillWhenNeighborMissesTheTabSpan() {
        // A neighbor stacked far above doesn't overlap a mid-height left-edge tab,
        // so sliding off the (locally outer) left edge truly leaves the screen.
        let rightVisible = CGRect(x: 1000, y: 0, width: 1000, height: 760)
        let neighborAbove = CGRect(x: 0, y: 2000, width: 1000, height: 800)
        let resting = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: rightVisible)

        XCTAssertFalse(EdgeLayout.hiddenFrameSpillsOntoOtherScreens(
            edge: .left, restingTabFrame: resting, screenVisibleFrame: rightVisible, otherScreenFrames: [neighborAbove]))
    }

    func testSliverTabFrameStaysOnScreenFlushToEdge() {
        let reveal: CGFloat = 3
        for edge in Edge.allCases {
            let resting = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let sliver = EdgeLayout.sliverTabFrame(edge: edge, restingTabFrame: resting, reveal: reveal)

            // Entirely within its own screen — never spills onto a neighbor.
            XCTAssertTrue(visible.insetBy(dx: -0.01, dy: -0.01).contains(sliver), "sliver left the screen on \(edge): \(sliver)")
            switch edge {
            case .left:
                XCTAssertEqual(sliver.minX, visible.minX, accuracy: 0.001)   // flush, on-screen
                XCTAssertEqual(sliver.width, reveal, accuracy: 0.001)
                XCTAssertEqual(sliver.minY, resting.minY, accuracy: 0.001)   // along-edge unchanged
            case .right:
                XCTAssertEqual(sliver.maxX, visible.maxX, accuracy: 0.001)
                XCTAssertEqual(sliver.width, reveal, accuracy: 0.001)
            case .top:
                XCTAssertEqual(sliver.maxY, visible.maxY, accuracy: 0.001)
                XCTAssertEqual(sliver.height, reveal, accuracy: 0.001)
            case .bottom:
                XCTAssertEqual(sliver.minY, visible.minY, accuracy: 0.001)
                XCTAssertEqual(sliver.height, reveal, accuracy: 0.001)
            }
        }
    }

    // MARK: Drawer placement (flush to edge) + opened tab

    func testOpenDrawerIsFlushToItsEdge() {
        let tabR = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: visible)
        let dR = EdgeLayout.openDrawerFrame(edge: .right, tabFrame: tabR, contentSize: CGSize(width: 300, height: 400), in: visible)
        XCTAssertEqual(dR.maxX, visible.maxX, accuracy: 0.001)

        let tabB = EdgeLayout.tabFrame(edge: .bottom, position: 0.5, size: pill, in: visible)
        let dB = EdgeLayout.openDrawerFrame(edge: .bottom, tabFrame: tabB, contentSize: CGSize(width: 300, height: 400), in: visible)
        XCTAssertEqual(dB.minY, visible.minY, accuracy: 0.001)
    }

    func testOpenDrawerIsCenteredOnTabAlongEdge() {
        let tab = EdgeLayout.tabFrame(edge: .bottom, position: 0.3, size: pill, in: visible)
        let drawer = EdgeLayout.openDrawerFrame(edge: .bottom, tabFrame: tab, contentSize: CGSize(width: 300, height: 200), in: visible)
        XCTAssertEqual(drawer.midX, tab.midX, accuracy: 0.001)
    }

    func testOpenDrawerIsClampedToScreen() {
        for edge in Edge.allCases {
            let tab = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let drawer = EdgeLayout.openDrawerFrame(edge: edge, tabFrame: tab,
                                                    contentSize: CGSize(width: 9000, height: 9000), in: visible)
            XCTAssertTrue(visible.insetBy(dx: -0.5, dy: -0.5).contains(drawer),
                          "drawer left the screen on \(edge): \(drawer)")
        }
    }

    func testOpenedTabRidesOnDrawerInnerFace() {
        // The tab is pushed in from the edge to sit flush on the drawer's inner
        // face — same size, touching, not overlapping the drawer's interior.
        for edge in Edge.allCases {
            let tab = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let drawer = EdgeLayout.openDrawerFrame(edge: edge, tabFrame: tab, contentSize: CGSize(width: 300, height: 300), in: visible)
            let opened = EdgeLayout.openedTabFrame(edge: edge, restingTabFrame: tab, drawerFrame: drawer)

            XCTAssertEqual(opened.width, tab.width, accuracy: 0.001)
            XCTAssertEqual(opened.height, tab.height, accuracy: 0.001)
            switch edge {
            case .right:  XCTAssertEqual(opened.maxX, drawer.minX, accuracy: 0.001)
            case .left:   XCTAssertEqual(opened.minX, drawer.maxX, accuracy: 0.001)
            case .top:    XCTAssertEqual(opened.maxY, drawer.minY, accuracy: 0.001)
            case .bottom: XCTAssertEqual(opened.minY, drawer.maxY, accuracy: 0.001)
            }
            XCTAssertFalse(opened.insetBy(dx: 0.5, dy: 0.5).intersects(drawer),
                           "opened tab overlaps drawer interior on \(edge)")
        }
    }

    // MARK: Drawer inner-corner squaring (flush tab join)

    func testCenteredTabKeepsBothDrawerCornersRounded() {
        // Drawer centered on the tab with the straight run ≥ tab length → neither
        // inner corner needs squaring.
        let radius: CGFloat = 14
        let tab = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: visible)
        let drawer = EdgeLayout.openDrawerFrame(edge: .left, tabFrame: tab,
                                                contentSize: CGSize(width: 300, height: pill.height + 2 * radius), in: visible)
        let corners = EdgeLayout.drawerInnerCornersToSquare(edge: .left, tabFrame: tab, drawerFrame: drawer, radius: radius)
        XCTAssertFalse(corners.start)
        XCTAssertFalse(corners.end)
    }

    func testTabAtBottomSquaresOnlyTheBottomInnerCorner() {
        // A clamped drawer near the bottom: the tab sits at the bottom corner (the
        // reported bug), so only the bottom (end) inner corner is squared.
        let radius: CGFloat = 14
        let tab = EdgeLayout.tabFrame(edge: .left, position: 1.0, size: pill, in: visible)   // flush to the bottom
        let drawer = EdgeLayout.openDrawerFrame(edge: .left, tabFrame: tab,
                                                contentSize: CGSize(width: 300, height: 400), in: visible)
        let corners = EdgeLayout.drawerInnerCornersToSquare(edge: .left, tabFrame: tab, drawerFrame: drawer, radius: radius)
        XCTAssertFalse(corners.start)
        XCTAssertTrue(corners.end)
    }

    func testTabAtTopSquaresOnlyTheTopInnerCorner() {
        let radius: CGFloat = 14
        let tab = EdgeLayout.tabFrame(edge: .right, position: 0.0, size: pill, in: visible)   // flush to the top
        let drawer = EdgeLayout.openDrawerFrame(edge: .right, tabFrame: tab,
                                                contentSize: CGSize(width: 300, height: 400), in: visible)
        let corners = EdgeLayout.drawerInnerCornersToSquare(edge: .right, tabFrame: tab, drawerFrame: drawer, radius: radius)
        XCTAssertTrue(corners.start)
        XCTAssertFalse(corners.end)
    }

    func testTabAtTrailingEndSquaresOnlyTheTrailingInnerCorner() {
        // Horizontal edge: a tab clamped to the right squares the trailing corner.
        let radius: CGFloat = 14
        let wide = CGSize(width: 120, height: 40)
        let tab = EdgeLayout.tabFrame(edge: .bottom, position: 1.0, size: wide, in: visible)
        let drawer = EdgeLayout.openDrawerFrame(edge: .bottom, tabFrame: tab,
                                                contentSize: CGSize(width: 300, height: 300), in: visible)
        let corners = EdgeLayout.drawerInnerCornersToSquare(edge: .bottom, tabFrame: tab, drawerFrame: drawer, radius: radius)
        XCTAssertFalse(corners.start)
        XCTAssertTrue(corners.end)
    }

    func testNudgedDrawerStaysOnScreenSameSize() {
        for edge in Edge.allCases {
            let tab = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let open = EdgeLayout.openDrawerFrame(edge: edge, tabFrame: tab, contentSize: CGSize(width: 300, height: 300), in: visible)
            let nudged = EdgeLayout.nudgedDrawerFrame(edge: edge, openFrame: open, by: 22)
            XCTAssertEqual(nudged.size.width, open.size.width, accuracy: 0.001)
            XCTAssertEqual(nudged.size.height, open.size.height, accuracy: 0.001)   // pure translation
            // Nudge is inward, so it stays within the screen (never crosses the edge).
            XCTAssertTrue(visible.contains(nudged), "nudged drawer left the screen for \(edge)")
        }
    }

    // MARK: Drag inversion

    func testPositionForPointRoundTripsVerticalEdge() {
        let tab = EdgeLayout.tabFrame(edge: .right, position: 0.3, size: pill, in: visible)
        let center = CGPoint(x: tab.midX, y: tab.midY)
        let recovered = EdgeLayout.position(forPoint: center, edge: .right, in: visible)
        XCTAssertEqual(recovered, 0.3, accuracy: 0.02)
    }

    func testPositionForPointRoundTripsHorizontalEdge() {
        let tab = EdgeLayout.tabFrame(edge: .bottom, position: 0.7, size: pill, in: visible)
        let center = CGPoint(x: tab.midX, y: tab.midY)
        let recovered = EdgeLayout.position(forPoint: center, edge: .bottom, in: visible)
        XCTAssertEqual(recovered, 0.7, accuracy: 0.02)
    }

    func testPositionForTabFrameReturnsExactEndpointsOnEveryEdge() {
        for edge in Edge.allCases {
            let size = edge.isVertical ? pill : CGSize(width: pill.height, height: pill.width)
            let start = EdgeLayout.tabFrame(edge: edge, position: 0, size: size, in: visible)
            let end = EdgeLayout.tabFrame(edge: edge, position: 1, size: size, in: visible)

            XCTAssertEqual(EdgeLayout.position(forTabFrame: start, edge: edge, in: visible), 0,
                           "start endpoint was not exact on \(edge)")
            XCTAssertEqual(EdgeLayout.position(forTabFrame: end, edge: edge, in: visible), 1,
                           "end endpoint was not exact on \(edge)")
        }
    }

    func testPositionForTabFrameUsesCenterForInteriorPointsOnEveryEdge() {
        for edge in Edge.allCases {
            let size = edge.isVertical ? pill : CGSize(width: pill.height, height: pill.width)
            for position in [0.2, 0.5, 0.8] {
                let frame = EdgeLayout.tabFrame(edge: edge, position: position, size: size, in: visible)
                let recovered = EdgeLayout.position(forTabFrame: frame, edge: edge, in: visible)
                XCTAssertEqual(recovered, position, accuracy: 0.000_001,
                               "interior position did not round-trip on \(edge)")
            }
        }
    }

    func testPositionForTabFrameToleratesFloatNoiseAtEveryEndpoint() {
        let noise: CGFloat = 0.0005
        for edge in Edge.allCases {
            let size = edge.isVertical ? pill : CGSize(width: pill.height, height: pill.width)
            for delta in [-noise, noise] {
                var start = EdgeLayout.tabFrame(edge: edge, position: 0, size: size, in: visible)
                var end = EdgeLayout.tabFrame(edge: edge, position: 1, size: size, in: visible)
                if edge.isVertical {
                    start.origin.y += delta
                    end.origin.y += delta
                } else {
                    start.origin.x += delta
                    end.origin.x += delta
                }

                XCTAssertEqual(EdgeLayout.position(forTabFrame: start, edge: edge, in: visible), 0,
                               "start float noise lost the endpoint on \(edge)")
                XCTAssertEqual(EdgeLayout.position(forTabFrame: end, edge: edge, in: visible), 1,
                               "end float noise lost the endpoint on \(edge)")
            }
        }
    }

    func testPositionForTabFrameRoundTripsAcrossChangedResolution() {
        let oldVisible = CGRect(x: 1440, y: 75, width: 1920, height: 1040)
        let newVisible = CGRect(x: -1280, y: -40, width: 1280, height: 700)

        for edge in Edge.allCases {
            let size = edge.isVertical ? pill : CGSize(width: pill.height, height: pill.width)
            for original in [0.0, 0.37, 1.0] {
                let oldFrame = EdgeLayout.tabFrame(edge: edge, position: original, size: size, in: oldVisible)
                let persisted = EdgeLayout.position(forTabFrame: oldFrame, edge: edge, in: oldVisible)
                let restored = EdgeLayout.tabFrame(edge: edge, position: persisted, size: size, in: newVisible)
                let roundTripped = EdgeLayout.position(forTabFrame: restored, edge: edge, in: newVisible)

                XCTAssertEqual(persisted, original, accuracy: 0.000_001,
                               "old resolution changed the anchor on \(edge)")
                XCTAssertEqual(roundTripped, original, accuracy: 0.000_001,
                               "new resolution changed the anchor on \(edge)")
            }
        }
    }

    func testPlacementWorksWithOffsetVisibleFrame() {
        // A secondary display's visibleFrame has a non-zero origin.
        let secondary = CGRect(x: 1440, y: 100, width: 1280, height: 700)
        let frame = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: secondary)
        XCTAssertEqual(frame.minX, secondary.minX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, secondary.midY, accuracy: 0.001)
    }

    // MARK: Z-order (overlapping tabs sharing an edge)

    func testFrontmostOnVerticalEdgeIsTheHigherTab() {
        // Two overlapping right-edge tabs: the top one (higher maxY) draws in front.
        let top = CGRect(x: 960, y: 400, width: 40, height: 120)
        let bottom = CGRect(x: 960, y: 320, width: 40, height: 120)   // overlaps, lower
        XCTAssertEqual(EdgeLayout.isFrontmost(top, bottom, edge: .right), true)
        XCTAssertEqual(EdgeLayout.isFrontmost(bottom, top, edge: .right), false)
        XCTAssertEqual(EdgeLayout.isFrontmost(top, bottom, edge: .left), true)   // same rule on the left edge
    }

    func testFrontmostOnHorizontalEdgeIsTheLeftTab() {
        // Two overlapping bottom-edge tabs: the left one (lower minX) draws in front.
        let left = CGRect(x: 300, y: 0, width: 120, height: 40)
        let right = CGRect(x: 380, y: 0, width: 120, height: 40)   // overlaps, further right
        XCTAssertEqual(EdgeLayout.isFrontmost(left, right, edge: .bottom), true)
        XCTAssertEqual(EdgeLayout.isFrontmost(right, left, edge: .bottom), false)
        XCTAssertEqual(EdgeLayout.isFrontmost(left, right, edge: .top), true)   // same rule on the top edge
    }

    func testFrontmostIsNilForLevelTabs() {
        // Level on the along-edge axis → no geometric winner; the caller breaks the tie.
        let a = CGRect(x: 960, y: 400, width: 40, height: 120)
        let b = CGRect(x: 940, y: 400, width: 40, height: 120)   // same maxY
        XCTAssertNil(EdgeLayout.isFrontmost(a, b, edge: .right))

        let c = CGRect(x: 300, y: 0, width: 120, height: 40)
        let d = CGRect(x: 300, y: 20, width: 120, height: 40)    // same minX
        XCTAssertNil(EdgeLayout.isFrontmost(c, d, edge: .bottom))
    }

    // MARK: De-overlap (snap the newcomer; never move the incumbents)

    func testSnapWithNoFixedFramesLeavesTabPut() {
        let f = EdgeLayout.tabFrame(edge: .right, position: 0.3, size: pill, in: visible)
        let snapped = EdgeLayout.snappedAlongEdge(incoming: f, fixed: [], edge: .right, gap: 6, in: visible)
        XCTAssertEqual(snapped, f)
    }

    func testNonOverlappingTabIsLeftWhereItIs() {
        // The incoming tab is far from the only fixed one, so it doesn't move.
        let fixed = EdgeLayout.tabFrame(edge: .right, position: 0.1, size: pill, in: visible)
        let incoming = EdgeLayout.tabFrame(edge: .right, position: 0.9, size: pill, in: visible)
        let snapped = EdgeLayout.snappedAlongEdge(incoming: incoming, fixed: [fixed], edge: .right, gap: 6, in: visible)
        XCTAssertEqual(snapped, incoming)
    }

    func testOverlappingVerticalTabSnapsClearKeepingFlushAxis() {
        // Drop a right-edge tab right on top of a fixed one: it slides just clear with
        // the gap and stays flush to the right edge; the fixed tab is never returned
        // (the caller leaves it untouched).
        let gap: CGFloat = 6
        let fixed = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: visible)
        let incoming = fixed   // exactly overlapping
        let snapped = EdgeLayout.snappedAlongEdge(incoming: incoming, fixed: [fixed], edge: .right, gap: gap, in: visible)

        XCTAssertEqual(snapped.minX, fixed.minX, accuracy: 0.001)         // still flush right
        XCTAssertEqual(snapped.size, fixed.size)                          // unresized
        XCTAssertFalse(snapped.insetBy(dx: 0.5, dy: 0.5).intersects(fixed))
        // Exactly `gap` between the two pills (snapped sits just above, higher y).
        XCTAssertEqual(snapped.minY, fixed.maxY + gap, accuracy: 0.001)
    }

    func testOverlappingHorizontalTabSnapsClearKeepingFlushAxis() {
        let gap: CGFloat = 6
        let wide = CGSize(width: 120, height: 40)
        let fixed = EdgeLayout.tabFrame(edge: .bottom, position: 0.5, size: wide, in: visible)
        let snapped = EdgeLayout.snappedAlongEdge(incoming: fixed, fixed: [fixed], edge: .bottom, gap: gap, in: visible)

        XCTAssertEqual(snapped.minY, fixed.minY, accuracy: 0.001)         // still flush bottom
        XCTAssertFalse(snapped.insetBy(dx: 0.5, dy: 0.5).intersects(fixed))
        // Slides to whichever side is nearer; with an exact overlap that's the lower x.
        XCTAssertEqual(snapped.maxX, fixed.minX - gap, accuracy: 0.001)
    }

    func testSnapPicksTheNearerSide() {
        // The incoming tab overlaps a fixed one but its centre sits *below* the fixed
        // centre, so the nearest legal slot is just below it (snap down, not up).
        let gap: CGFloat = 6
        let fixed = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: visible)
        let incoming = fixed.offsetBy(dx: 0, dy: -pill.height * 0.4)   // mostly below the fixed tab
        let snapped = EdgeLayout.snappedAlongEdge(incoming: incoming, fixed: [fixed], edge: .right, gap: gap, in: visible)
        XCTAssertEqual(snapped.maxY, fixed.minY - gap, accuracy: 0.001)   // tucked just below
    }

    func testSnapSlidesPastAWholeRunOfFixedTabs() {
        // Two fixed tabs sit adjacent (a packed run); a third dropped onto them clears
        // the entire run rather than trying to wedge between them.
        let gap: CGFloat = 6
        let upper = EdgeLayout.tabFrame(edge: .right, position: 0.4, size: pill, in: visible)
        let lower = CGRect(x: upper.minX, y: upper.minY - pill.height - gap, width: pill.width, height: pill.height)
        let incoming = upper   // dropped onto the top of the run
        let snapped = EdgeLayout.snappedAlongEdge(incoming: incoming, fixed: [upper, lower], edge: .right, gap: gap, in: visible)
        XCTAssertFalse(snapped.insetBy(dx: 0.5, dy: 0.5).intersects(upper))
        XCTAssertFalse(snapped.insetBy(dx: 0.5, dy: 0.5).intersects(lower))
        XCTAssertEqual(snapped.minY, upper.maxY + gap, accuracy: 0.001)   // above the whole run
    }

    func testSnappedTabStaysOnScreen() {
        // A fixed tab pinned at the very top forces the incoming one (also at the top)
        // to snap downward — and it must stay fully on-screen.
        let fixed = EdgeLayout.tabFrame(edge: .right, position: 0.0, size: pill, in: visible)
        let snapped = EdgeLayout.snappedAlongEdge(incoming: fixed, fixed: [fixed], edge: .right, gap: 6, in: visible)
        XCTAssertGreaterThanOrEqual(snapped.minY, visible.minY - 0.001)
        XCTAssertLessThanOrEqual(snapped.maxY, visible.maxY + 0.001)
        XCTAssertFalse(snapped.insetBy(dx: 0.5, dy: 0.5).intersects(fixed))
    }

    func testFoldingSnapIsIdempotentOnAnAlreadyDeOverlappedLayout() {
        // The controller persists the de-overlapped positions; this is the property
        // that makes that safe — folding the snap over the *result* (same order)
        // reproduces it exactly, so a later reconcile re-derives the same frames and
        // nothing drifts. Start from three exactly-overlapping pills.
        let gap = EdgeLayout.minTabGap
        let start = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: visible)
        func fold(_ frames: [CGRect]) -> [CGRect] {
            var placed: [CGRect] = []
            for f in frames {
                placed.append(EdgeLayout.snappedAlongEdge(incoming: f, fixed: placed, edge: .right, gap: gap, in: visible))
            }
            return placed
        }
        let once = fold([start, start, start])
        let twice = fold(once)
        for (a, b) in zip(once, twice) {
            XCTAssertEqual(a.minY, b.minY, accuracy: 0.001)   // no drift on re-fold
            XCTAssertEqual(a.minX, b.minX, accuracy: 0.001)
        }
    }

    func testPersistedPositionRebuildsTheSameFrame() {
        // The controller persists a de-overlapped frame with the frame-aware inverse
        // (`position(forTabFrame:)`) and rebuilds it next
        // reconcile (`tabFrame(position:)`). That inverse must be pixel-exact, or the
        // rebuilt frame drifts, re-snaps, and the tab-jumping bug returns. The fold
        // idempotency test assumes this identity; pin it directly at sub-pixel tolerance
        // on both axes (vertical and horizontal edges).
        for edge in [Edge.right, .bottom] {
            let size = edge.isVertical ? pill : CGSize(width: pill.height, height: pill.width)
            let start = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: size, in: visible)
            var placed: [CGRect] = []
            for f in [start, start, start] {
                placed.append(EdgeLayout.snappedAlongEdge(incoming: f, fixed: placed,
                                                          edge: edge, gap: EdgeLayout.minTabGap, in: visible))
            }
            for f in placed {
                let pos = EdgeLayout.position(forTabFrame: f, edge: edge, in: visible)
                let rebuilt = EdgeLayout.tabFrame(edge: edge, position: pos, size: size, in: visible)
                XCTAssertEqual(rebuilt.minX, f.minX, accuracy: 0.001, "drift on \(edge)")
                XCTAssertEqual(rebuilt.minY, f.minY, accuracy: 0.001, "drift on \(edge)")
            }
        }
    }

    func testFoldingSnapOverAStackLeavesIncumbentsPutAndMovesOnlyTheNewcomer() {
        // Mirrors the controller's de-overlap fold: place tabs in stacking order, each
        // snapped against the ones already placed. Two non-overlapping incumbents must
        // not budge; a third dropped on top of one is the only one that moves. Uses a
        // positive gap so "snapped clear" is unambiguous, independent of how the
        // configured `minTabGap` is tuned.
        let gap: CGFloat = 6
        let a = EdgeLayout.tabFrame(edge: .right, position: 0.25, size: pill, in: visible)
        let b = EdgeLayout.tabFrame(edge: .right, position: 0.75, size: pill, in: visible)
        let newcomer = a   // dropped onto incumbent `a`

        var placed: [CGRect] = []
        for f in [a, b, newcomer] {
            placed.append(EdgeLayout.snappedAlongEdge(incoming: f, fixed: placed, edge: .right, gap: gap, in: visible))
        }
        XCTAssertEqual(placed[0], a)   // first incumbent untouched
        XCTAssertEqual(placed[1], b)   // second incumbent untouched
        XCTAssertFalse(placed[2].insetBy(dx: 0.5, dy: 0.5).intersects(a))   // newcomer snapped clear of `a`
        XCTAssertFalse(placed[2].insetBy(dx: 0.5, dy: 0.5).intersects(b))
    }

    // MARK: Position snapping (drag magnetization)

    func testSnappedPositionLocksToNearestGuideWithinTolerance() {
        let near = EdgeLayout.snappedPosition(0.49, tolerance: 0.03)
        XCTAssertEqual(near.position, 0.5, accuracy: 0.0001)
        XCTAssertEqual(near.snappedGuide, 0.5)

        let edge = EdgeLayout.snappedPosition(0.02, tolerance: 0.03)
        XCTAssertEqual(edge.position, 0.0, accuracy: 0.0001)
        XCTAssertEqual(edge.snappedGuide, 0.0)
    }

    func testSnappedPositionLeavesPositionWhenNoGuideIsClose() {
        let result = EdgeLayout.snappedPosition(0.40, tolerance: 0.03)   // 0.10 from 0.5, 0.15 from 0.25
        XCTAssertEqual(result.position, 0.40, accuracy: 0.0001)
        XCTAssertNil(result.snappedGuide)
    }

    func testSnappedPositionAcceptsNeighborGuides() {
        // A neighbor position passed in as a guide magnetizes too.
        let result = EdgeLayout.snappedPosition(0.31, guides: [0, 0.3, 1], tolerance: 0.03)
        XCTAssertEqual(result.position, 0.3, accuracy: 0.0001)
        XCTAssertEqual(result.snappedGuide, 0.3)
    }
}
