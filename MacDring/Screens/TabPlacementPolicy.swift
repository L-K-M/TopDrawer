#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation   // CGRect/CGFloat live in Foundation on Linux
#endif

/// Pure placement decisions lifted out of `TabController` (LP-09): given value inputs
/// — a tab's anchor, the connected displays, the disconnect policy, the neighbours on a
/// shared edge — it returns *what to do*, and the controller keeps doing the AppKit side
/// effects (placing/showing/hiding windows, writing anchors back). No global state, so
/// it's fully unit-testable on both platforms. See PLAN.md §5–6.
enum TabPlacementPolicy {

    // MARK: Reconcile — which display a tab lands on

    /// Where a tab's window belongs, given its own display and the main display.
    /// `Display` is whatever the caller works in (an `NSScreen` in the app, a stand-in
    /// in tests); a `.place` carries the resolved display so the caller needn't re-derive
    /// it. Deliberately not constrained to `Equatable` — only tests compare these.
    enum TabPlacement<Display> {
        /// Show the tab on this display — its own if connected, otherwise the main
        /// display under the move-to-main policy.
        case place(Display)
        /// Hide the tab until its display returns (the park policy, or no main display).
        case park
    }

    /// The reconcile rule: a tab lands on its own display when that display is connected;
    /// otherwise, under `.moveToMain`, on the main display when there is one; otherwise it
    /// parks. Pass `anchoredDisplay` = the tab's own display if connected (else `nil`) and
    /// `mainDisplay` = the main display (else `nil`).
    static func placement<Display>(anchoredDisplay: Display?, mainDisplay: Display?,
                                   disconnectPolicy: DisconnectPolicy) -> TabPlacement<Display> {
        if let anchoredDisplay { return .place(anchoredDisplay) }
        if disconnectPolicy == .moveToMain, let mainDisplay { return .place(mainDisplay) }
        return .park
    }

    // MARK: De-overlap — spacing tabs that share a display + edge

    /// One tab entering the de-overlap fold.
    struct DeOverlapInput {
        let id: UUID
        /// Stacking order (higher = more recently stacked, so it yields).
        let order: Int
        /// The tab's stored fractional position along the edge.
        let position: Double
        /// The tab's current resting frame, in screen coordinates.
        let restingFrame: CGRect
        /// Whether the tab is sitting on its *own* anchored display (not a move-to-main
        /// guest). Only own-display tabs persist their settled position; a guest is
        /// de-overlapped on screen only, so its stored anchor keeps pointing at the
        /// display it must restore to ("stable restore is sacred").
        let isOnOwnDisplay: Bool
    }

    /// One tab's decision out of the fold.
    struct DeOverlapResult: Equatable {
        let id: UUID
        /// The frame the tab should rest at after de-overlapping.
        let settledFrame: CGRect
        /// The fractional position to write back onto the tab's anchor, or `nil` to leave
        /// the stored anchor alone — a guest, or a snap that didn't move the tab beyond
        /// float noise.
        let persistedPosition: Double?
    }

    /// Spaces tabs that share a display + edge so they don't render on top of one another.
    /// Tabs are placed in stacking order (`order`, then `position`, then id), so the
    /// most-recently-stacked tab — the one just dragged or added — is the one that yields
    /// while the tabs already there stay put. Each tab keeps its fractional position
    /// unless it would overlap one already placed, in which case it snaps to the nearest
    /// legal gap (`EdgeLayout.snappedAlongEdge`). Results come back in placement order.
    static func deOverlap(_ inputs: [DeOverlapInput], edge: Edge, gap: CGFloat,
                          in visible: CGRect) -> [DeOverlapResult] {
        let sorted = inputs.sorted {
            ($0.order, $0.position, $0.id.uuidString) < ($1.order, $1.position, $1.id.uuidString)
        }
        var placed: [CGRect] = []
        var results: [DeOverlapResult] = []
        for input in sorted {
            let snapped = EdgeLayout.snappedAlongEdge(incoming: input.restingFrame, fixed: placed,
                                                      edge: edge, gap: gap, in: visible)
            placed.append(snapped)
            // Persist only when this is the tab's own display and the snap actually moved
            // it (beyond float noise) — matching TabController's original guard.
            let moved = abs(snapped.minX - input.restingFrame.minX) > 0.5
                || abs(snapped.minY - input.restingFrame.minY) > 0.5
            let persisted = (input.isOnOwnDisplay && moved)
                ? EdgeLayout.position(forTabFrame: snapped, edge: edge, in: visible)
                : nil
            results.append(DeOverlapResult(id: input.id, settledFrame: snapped, persistedPosition: persisted))
        }
        return results
    }
}

extension TabPlacementPolicy.TabPlacement: Equatable where Display: Equatable {}
