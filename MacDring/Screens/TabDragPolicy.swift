import Foundation   // UUID (and, on Linux, CGRect/CGFloat) live here
#if canImport(CoreGraphics)
import CoreGraphics  // macOS: CGRect/CGFloat come from here; Foundation still vends UUID
#endif

/// Pure drag-and-restack decisions lifted out of `TabController` (LP-10): given value
/// inputs — the drag target's raw position, the neighbouring tabs' fractions on the
/// target edge, and the tabs' resting frames — it returns *what to do* (where the pill
/// magnetizes, whether the alignment haptic fires, the front-to-back order to restack,
/// the stacking slot for a newcomer), while the controller keeps the AppKit side
/// effects (moving windows, firing the haptic, remembering the last guide, reading
/// screens). The geometry primitives it builds on live in `EdgeLayout`; this layer is
/// the orchestration on top. No global state, so it's fully unit-testable on both
/// platforms. See PLAN.md §5–6.
enum TabDragPolicy {

    // MARK: Magnetization — where a dragged pill snaps along its edge

    /// The dragged pill's position magnetized to the quarter guides (0/¼/½/¾/1) **and**
    /// to its neighbours' fractional positions, plus the guide it locked onto (`nil` =
    /// free) for haptic timing. Neighbour fractions join the fixed quarter guides so the
    /// pill lines up with a tab already on the edge, not only with the quarter points;
    /// `EdgeLayout.snappedPosition` then picks the nearest guide within tolerance.
    static func magnetize(position: Double, neighbours: [Double],
                          guides: [Double] = EdgeLayout.snapGuides) -> (position: Double, guide: Double?) {
        let snap = EdgeLayout.snappedPosition(position, guides: guides + neighbours)
        return (snap.position, snap.snappedGuide)
    }

    /// Whether the alignment haptic should fire as the magnetized guide moves from
    /// `previous` to `current`, and the guide to remember for next time. It fires once
    /// when the pill *locks onto* a guide — the guide changed and is non-nil — so a
    /// single tap marks the snap rather than a buzz on every mouse-move while it stays
    /// snapped, and nothing fires when it slips free (`current` nil). The controller
    /// performs the haptic and stores the returned guide.
    static func alignmentHaptic(current: Double?, previous: Double?) -> (fire: Bool, guide: Double?) {
        (fire: current != previous && current != nil, guide: current)
    }

    // MARK: Restack — the front-to-back z-order among tabs sharing an edge

    /// One tab feeding the restack decision: its id and current resting frame.
    struct RestackInput {
        let id: UUID
        let restingFrame: CGRect
    }

    /// The ids of tabs sharing a display + edge, ordered **front to back**, so where
    /// they overlap (allowed once `minTabGap` goes negative) the leading tab — top on a
    /// vertical edge, left on a horizontal one — draws in front, reading top-to-bottom /
    /// left-to-right. Ties on the along-edge axis break by id so the order is stable
    /// (`EdgeLayout.isFrontmost` returns `nil` when two tabs are level). The caller tucks
    /// each window below the previous one in this order.
    static func restackOrder(_ inputs: [RestackInput], edge: Edge) -> [UUID] {
        inputs.sorted { a, b in
            EdgeLayout.isFrontmost(a.restingFrame, b.restingFrame, edge: edge)
                ?? (a.id.uuidString < b.id.uuidString)
        }.map(\.id)
    }

    /// The stacking `order` for a freshly placed tab (a drop, an edge move, a new tab):
    /// one past the highest order already on that edge/display, so the de-overlap pass
    /// treats it as the newcomer that yields while the tabs already there stay put.
    /// `existingOrders` are the orders of the other tabs sharing the edge/display;
    /// delegates the cap-safe increment to `PersistedLayoutBounds.nextOrder`.
    static func nextStackOrder(existingOrders: [Int]) -> Int {
        PersistedLayoutBounds.nextOrder(after: existingOrders.max())
    }
}
