#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation   // CGRect/CGPoint/CGSize/CGFloat live in Foundation on Linux
#endif

/// Pure geometry: turns a tab's `ScreenAnchor` into on-screen frames, positions
/// a drawer adjacent to its tab, and inverts a drag point or settled tab frame back
/// into a fractional position. All coordinates are AppKit/Cocoa screen coordinates (origin
/// bottom-left, y grows upward). No global state, so it's fully unit-testable.
/// See PLAN.md §5–6.
enum EdgeLayout {

    /// Gap between a tab pill and its drawer.
    static let drawerGap: CGFloat = 8

    /// Minimum spacing kept between two tabs that share an edge when one snaps clear
    /// of another. May be **negative**, which lets tabs overlap by up to that many
    /// points before the snap separates them — so they can sit very close, even
    /// slightly stacked, rather than being forced apart.
    static let minTabGap: CGFloat = -16

    // MARK: Tab placement

    /// Frame for a tab pill of `size`, anchored to `edge` at fractional
    /// `position` within `visibleFrame`.
    static func tabFrame(edge: Edge, position: Double, size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let p = CGFloat(ScreenAnchor.clampPosition(position))
        switch edge {
        case .left:
            return CGRect(x: visibleFrame.minX,
                          y: yForVertical(position: p, height: size.height, in: visibleFrame),
                          width: size.width, height: size.height)
        case .right:
            return CGRect(x: visibleFrame.maxX - size.width,
                          y: yForVertical(position: p, height: size.height, in: visibleFrame),
                          width: size.width, height: size.height)
        case .top:
            return CGRect(x: xForHorizontal(position: p, width: size.width, in: visibleFrame),
                          y: visibleFrame.maxY - size.height,
                          width: size.width, height: size.height)
        case .bottom:
            return CGRect(x: xForHorizontal(position: p, width: size.width, in: visibleFrame),
                          y: visibleFrame.minY,
                          width: size.width, height: size.height)
        }
    }

    /// For left/right edges: `position` 0 = top, 1 = bottom. Returns the origin
    /// (bottom) y for a window of `height`, clamped within `visibleFrame`.
    private static func yForVertical(position p: CGFloat, height: CGFloat, in vf: CGRect) -> CGFloat {
        let centerY = vf.maxY - p * vf.height
        return clamp(centerY - height / 2, vf.minY, vf.maxY - height)
    }

    /// For top/bottom edges: `position` 0 = leading (left), 1 = trailing (right).
    private static func xForHorizontal(position p: CGFloat, width: CGFloat, in vf: CGRect) -> CGFloat {
        let centerX = vf.minX + p * vf.width
        return clamp(centerX - width / 2, vf.minX, vf.maxX - width)
    }

    /// The off-edge frame for an auto-hidden tab: the resting pill slid out past
    /// `edge` until only `reveal` points peek back onto the screen as a hover hint
    /// (Dock-style). Only the perpendicular (flush-to-edge) axis moves; the
    /// along-edge position is unchanged. See PLAN.md §13.
    static func hiddenTabFrame(edge: Edge, restingTabFrame f: CGRect, in vf: CGRect, reveal: CGFloat = 3) -> CGRect {
        var frame = f
        switch edge {
        case .left:   frame.origin.x = vf.minX - (f.width - reveal)
        case .right:  frame.origin.x = vf.maxX - reveal
        case .top:    frame.origin.y = vf.maxY - reveal
        case .bottom: frame.origin.y = vf.minY - (f.height - reveal)
        }
        return frame
    }

    /// A thin sliver flush at `edge`, shrunk to `reveal` points on the
    /// perpendicular axis and kept entirely on the tab's own screen (the along-edge
    /// axis is unchanged). Used to auto-hide a tab on an edge it *shares* with
    /// another display, where sliding off would spill onto the neighbor — this
    /// reclaims the space without leaving its screen, instead of fading. Pure, so
    /// it's unit-tested. See PLAN.md §13.
    static func sliverTabFrame(edge: Edge, restingTabFrame f: CGRect, reveal: CGFloat = 3) -> CGRect {
        var frame = f
        switch edge {
        case .left:   frame.size.width = reveal
        case .right:  frame.origin.x = f.maxX - reveal; frame.size.width = reveal
        case .top:    frame.origin.y = f.maxY - reveal; frame.size.height = reveal
        case .bottom: frame.size.height = reveal
        }
        return frame
    }

    /// Whether auto-hiding by sliding the resting tab off `edge` would leave it
    /// visible on *another* display — true when a screen butts against that edge
    /// over the tab's span. On such a shared edge the pill can't actually go
    /// off-screen (it would land on the neighbor), so the caller shrinks it to a
    /// `sliverTabFrame` instead. Pure, so it's unit-tested. See PLAN.md §13.
    static func hiddenFrameSpillsOntoOtherScreens(edge: Edge, restingTabFrame: CGRect,
                                                  screenVisibleFrame: CGRect,
                                                  otherScreenFrames: [CGRect], reveal: CGFloat = 3) -> Bool {
        let hidden = hiddenTabFrame(edge: edge, restingTabFrame: restingTabFrame, in: screenVisibleFrame, reveal: reveal)
        return otherScreenFrames.contains { $0.intersects(hidden) }
    }

    // MARK: Drawer placement

    /// Frame for an opening drawer: it sits **flush against the screen edge**
    /// (like a physical drawer sliding out), sized `contentSize` (capped to the
    /// screen) and centered along the edge on the tab. The tab then rides on the
    /// drawer's inner face — see `openedTabFrame`. This is the "drawer pushes the
    /// tab inward" behavior.
    static func openDrawerFrame(edge: Edge, tabFrame: CGRect, contentSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let w = min(contentSize.width, visibleFrame.width)
        let h = min(contentSize.height, visibleFrame.height)
        switch edge {
        case .left:
            return CGRect(x: visibleFrame.minX,
                          y: alignVertical(center: tabFrame.midY, height: h, in: visibleFrame),
                          width: w, height: h)
        case .right:
            return CGRect(x: visibleFrame.maxX - w,
                          y: alignVertical(center: tabFrame.midY, height: h, in: visibleFrame),
                          width: w, height: h)
        case .top:
            return CGRect(x: alignHorizontal(center: tabFrame.midX, width: w, in: visibleFrame),
                          y: visibleFrame.maxY - h,
                          width: w, height: h)
        case .bottom:
            return CGRect(x: alignHorizontal(center: tabFrame.midX, width: w, in: visibleFrame),
                          y: visibleFrame.minY,
                          width: w, height: h)
        }
    }

    /// Which inner corners of an open drawer must be squared so its tab joins the
    /// drawer flush. The tab rides the drawer's inward face; if it sits within
    /// `radius` of a corner (e.g. the drawer was clamped toward a screen edge, so
    /// the tab is no longer centered on it), that corner has to be square or a
    /// rounded notch shows at the seam. `start`/`end` run along the inward face:
    /// top→bottom for left/right edges, leading→trailing for top/bottom. Pure, so
    /// it's unit-tested. See PLAN.md §5.
    static func drawerInnerCornersToSquare(edge: Edge, tabFrame: CGRect, drawerFrame: CGRect,
                                           radius: CGFloat) -> (start: Bool, end: Bool) {
        let tolerance: CGFloat = 0.5   // ignore float noise when a centered tab just touches the curve
        if edge.isVertical {
            return (start: tabFrame.maxY > drawerFrame.maxY - radius + tolerance,   // near the top corner
                    end:   tabFrame.minY < drawerFrame.minY + radius - tolerance)   // near the bottom corner
        } else {
            return (start: tabFrame.minX < drawerFrame.minX + radius - tolerance,   // near the leading corner
                    end:   tabFrame.maxX > drawerFrame.maxX - radius + tolerance)   // near the trailing corner
        }
    }

    /// The tab's frame while its drawer is open: pushed in from the edge to ride
    /// flush on the drawer's inner face, keeping its size and along-edge center.
    static func openedTabFrame(edge: Edge, restingTabFrame: CGRect, drawerFrame: CGRect) -> CGRect {
        var frame = restingTabFrame
        switch edge {
        case .left:   frame.origin.x = drawerFrame.maxX
        case .right:  frame.origin.x = drawerFrame.minX - restingTabFrame.width
        case .top:    frame.origin.y = drawerFrame.minY - restingTabFrame.height
        case .bottom: frame.origin.y = drawerFrame.maxY
        }
        return frame
    }

    /// A small **inward** nudge of `openFrame` (toward the screen center), used as
    /// the start/end of the drawer's fade-slide. Nudging inward (rather than
    /// tucking off the edge) keeps the animation on the drawer's own screen, so it
    /// never bleeds onto an adjacent display at a shared edge.
    static func nudgedDrawerFrame(edge: Edge, openFrame: CGRect, by amount: CGFloat) -> CGRect {
        switch edge {
        case .left:   return openFrame.offsetBy(dx: amount, dy: 0)
        case .right:  return openFrame.offsetBy(dx: -amount, dy: 0)
        case .top:    return openFrame.offsetBy(dx: 0, dy: -amount)
        case .bottom: return openFrame.offsetBy(dx: 0, dy: amount)
        }
    }

    // MARK: De-overlap (tabs sharing an edge)

    /// Snaps a single `incoming` frame along `edge` to the nearest spot that clears
    /// every `fixed` frame by at least `gap` and stays on `visibleFrame` — **without
    /// moving any fixed frame**. "Nearest" is the smallest along-edge shift from where
    /// `incoming` sits, so a tab dropped near others slides just far enough to find a
    /// legal gap rather than shoving its neighbours along the edge. The cross-edge
    /// (flush-to-the-edge) axis is left untouched. Pure, so it's unit-tested. See
    /// PLAN.md §5.
    ///
    /// Callers de-overlap a whole edge by folding this over the tabs in stacking
    /// order: place each against the ones already placed, so incumbents keep their
    /// exact positions and only the most-recently-stacked tab yields.
    static func snappedAlongEdge(incoming: CGRect, fixed: [CGRect], edge: Edge, gap: CGFloat, in vf: CGRect) -> CGRect {
        let horizontal = !edge.isVertical

        // `a` is the distance from the edge's start (left for top/bottom, top for
        // left/right), so increasing `a` reads left→right or top→bottom.
        func a(of f: CGRect) -> CGFloat { horizontal ? f.minX - vf.minX : vf.maxY - f.maxY }
        func len(of f: CGRect) -> CGFloat { horizontal ? f.width : f.height }
        let axisMax = horizontal ? vf.width : vf.height

        let length = len(of: incoming)
        let upper = Swift.max(0, axisMax - length)                 // furthest start that stays on-screen
        let desired = Swift.min(Swift.max(a(of: incoming), 0), upper)

        func placed(at start: CGFloat) -> CGRect {
            var f = incoming
            if horizontal { f.origin.x = vf.minX + start }
            else { f.origin.y = vf.maxY - start - f.height }
            return f
        }

        guard !fixed.isEmpty, length > 0 else { return placed(at: desired) }

        // Each fixed frame becomes a blocked span widened by `gap` on both sides: a
        // start that lands outside every span clears its neighbour by at least `gap`.
        // Merge the (sorted) spans so adjacent tabs read as one run to slide past.
        let eps: CGFloat = 0.001
        var blocked: [(lo: CGFloat, hi: CGFloat)] = []
        for span in fixed.map({ (lo: a(of: $0) - gap, hi: a(of: $0) + len(of: $0) + gap) }).sorted(by: { $0.lo < $1.lo }) {
            if let last = blocked.last, span.lo <= last.hi + eps {
                blocked[blocked.count - 1].hi = Swift.max(last.hi, span.hi)
            } else {
                blocked.append(span)
            }
        }

        // A start is legal when the pill [start, start+length] overlaps no blocked run
        // and stays on-screen.
        func legal(_ start: CGFloat) -> Bool {
            start >= -eps && start <= upper + eps
                && !blocked.contains { $0.lo < start + length - eps && $0.hi > start + eps }
        }
        if legal(desired) { return placed(at: desired) }

        // The nearest legal start is either `desired` (handled) or flush against a run
        // boundary: ending at a run's near edge (`lo - length`) or starting at its far
        // edge (`hi`). Enumerate those, clamp on-screen, keep the legal one closest to
        // `desired`.
        let candidates = blocked.flatMap { [$0.lo - length, $0.hi] }
            .map { Swift.min(Swift.max($0, 0), upper) }
            .filter(legal)
        guard let best = candidates.min(by: { abs($0 - desired) < abs($1 - desired) }) else {
            return placed(at: desired)   // too crowded for a legal slot — leave it at desired
        }
        return placed(at: best)
    }

    // MARK: Z-order (overlapping tabs sharing an edge)

    /// Front-to-back order for two tab frames sharing an edge, so any overlap draws
    /// predictably: the **leading** tab is frontmost — top (higher `maxY`) on a
    /// vertical edge, leading/left (lower `minX`) on a horizontal one — reading
    /// top-to-bottom / left-to-right. Returns `true` if `a` should sit in front of `b`,
    /// `false` if behind, or `nil` when they're level on the along-edge axis (the
    /// caller breaks the tie, e.g. by id, to keep the order stable). Pure, so it's
    /// unit-tested.
    static func isFrontmost(_ a: CGRect, _ b: CGRect, edge: Edge) -> Bool? {
        if edge.isVertical {
            guard a.maxY != b.maxY else { return nil }
            return a.maxY > b.maxY
        } else {
            guard a.minX != b.minX else { return nil }
            return a.minX < b.minX
        }
    }

    private static func alignVertical(center: CGFloat, height: CGFloat, in vf: CGRect) -> CGFloat {
        clamp(center - height / 2, vf.minY, vf.maxY - height)
    }

    private static func alignHorizontal(center: CGFloat, width: CGFloat, in vf: CGRect) -> CGFloat {
        clamp(center - width / 2, vf.minX, vf.maxX - width)
    }

    // MARK: Position inversion

    /// The fractional position represented by a settled tab `frame`. A tab touching
    /// an along-edge boundary retains the exact endpoint anchor (`0` or `1`) rather
    /// than deriving an inset fraction from its center. Interior frames use the same
    /// center-based inverse as cursor targeting.
    static func position(forTabFrame frame: CGRect, edge: Edge, in visibleFrame: CGRect) -> Double {
        let tolerance: CGFloat = 0.001
        if edge.isVertical {
            if abs(frame.maxY - visibleFrame.maxY) <= tolerance { return 0 }
            if abs(frame.minY - visibleFrame.minY) <= tolerance { return 1 }
        } else {
            if abs(frame.minX - visibleFrame.minX) <= tolerance { return 0 }
            if abs(frame.maxX - visibleFrame.maxX) <= tolerance { return 1 }
        }
        return position(forPoint: CGPoint(x: frame.midX, y: frame.midY), edge: edge, in: visibleFrame)
    }

    /// The fractional position along `edge` for a screen-space point `p` — the
    /// point inverse used to target the cursor during drag-to-reposition.
    static func position(forPoint p: CGPoint, edge: Edge, in visibleFrame: CGRect) -> Double {
        switch edge {
        case .left, .right:
            guard visibleFrame.height > 0 else { return 0.5 }
            return ScreenAnchor.clampPosition(Double((visibleFrame.maxY - p.y) / visibleFrame.height))
        case .top, .bottom:
            guard visibleFrame.width > 0 else { return 0.5 }
            return ScreenAnchor.clampPosition(Double((p.x - visibleFrame.minX) / visibleFrame.width))
        }
    }

    // MARK: Drag magnetization (snap guides)

    /// The fractional guides a dragged tab magnetizes to: the quarter points along
    /// the edge. Combined at the call site with neighboring tabs' positions.
    static let snapGuides: [Double] = [0, 0.25, 0.5, 0.75, 1.0]

    /// Snaps a fractional `position` to the nearest `guide` within `tolerance`.
    /// Returns the (possibly unchanged) position and the guide it locked onto, or
    /// `nil` when nothing was close enough — the caller uses the guide identity to
    /// fire an alignment haptic only when the lock *changes*. Pure / unit-tested.
    static func snappedPosition(_ position: Double, guides: [Double] = snapGuides,
                                tolerance: Double = 0.03) -> (position: Double, snappedGuide: Double?) {
        guard let nearest = guides.min(by: { abs($0 - position) < abs($1 - position) }),
              abs(nearest - position) <= tolerance else {
            return (position, nil)
        }
        return (nearest, nearest)
    }

    // MARK: Helpers

    /// Clamps `v` to `[lo, hi]`; if the window is larger than the available
    /// range (hi < lo), pins to `lo` so it stays on-screen at the edge.
    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi > lo else { return lo }
        return Swift.min(Swift.max(v, lo), hi)
    }
}
