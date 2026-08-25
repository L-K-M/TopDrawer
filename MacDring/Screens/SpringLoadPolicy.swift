import Foundation   // TimeInterval (and, on Linux, CGRect/CGPoint/CGFloat)
#if canImport(CoreGraphics)
import CoreGraphics  // macOS: CG geometry comes from here
#endif

/// Pure spring-load / drag-peek decisions lifted out of `TabController` (LP-11): the
/// dwell timings and hover margins, whether a file-drag hover should spring a drawer
/// open, which concealed tabs a cursor reveals (from a wider "peek" zone while a file is
/// in flight), and how a single tab transitions between revealed and concealed. The
/// timers, monitors, and window side effects stay in the controller; these are pure
/// state-transition functions, so they're fully unit-testable on both platforms.
/// See PLAN.md §13.
enum SpringLoadPolicy {

    // MARK: Dwell timings & hover margins

    /// How long a file-drag hover must dwell on a tab before its drawer springs open.
    static let springOpenDelay: TimeInterval = 0.5
    /// How long an idle tab waits after the cursor leaves its zone before re-concealing.
    static let reConcealDelay: TimeInterval = 0.45
    /// How far past a tab's resting footprint the cursor still counts as hovering it (an
    /// easier target than the thin revealed sliver).
    static let revealSlop: CGFloat = 6
    /// The more generous margin used while a *file drag* nears a concealed tab, so
    /// spring-loading has a real pill to target rather than a 3 pt sliver.
    static let peekSlop: CGFloat = 60

    /// The hover margin to inset a tab's resting frame by: the wide peek margin while a
    /// file is being dragged, the tight reveal margin otherwise.
    static func slop(peeking: Bool) -> CGFloat { peeking ? peekSlop : revealSlop }

    // MARK: Spring-open — should a file-drag hover open the drawer

    /// What a drag-hover change should do to a tab's pending spring-open.
    enum SpringAction: Equatable {
        /// The drag left the tab — cancel any pending spring-open for it.
        case cancel
        /// The tab's drawer is already open — nothing to spring.
        case alreadyOpen
        /// Arm the spring-open: after `springOpenDelay`, open this tab's drawer.
        case scheduleOpen
    }

    /// Given whether the tab is currently drag-targeted and whether its drawer is already
    /// open, what the controller should do with its spring-open timer.
    static func springAction(isTargeted: Bool, isOpen: Bool) -> SpringAction {
        guard isTargeted else { return .cancel }
        return isOpen ? .alreadyOpen : .scheduleOpen
    }

    // MARK: Reveal — which concealed tabs the cursor reveals

    /// For a set of concealable tabs (given as their hover zones in screen coordinates),
    /// which ones the cursor at `mouse` should reveal. With `revealAllTogether`, hovering
    /// **any** zone reveals them all (so grouped tabs come out and go back together);
    /// otherwise each tab follows only its own zone. Order matches `zones`.
    static func reveals(zones: [CGRect], mouse: CGPoint, revealAllTogether: Bool) -> [Bool] {
        let revealAll = revealAllTogether && zones.contains { $0.contains(mouse) }
        return zones.map { revealAll || $0.contains(mouse) }
    }

    // MARK: Reveal transition — how one tab moves between revealed and concealed

    /// The state change to apply to one tab given its reveal decision.
    enum RevealTransition: Equatable {
        /// Reveal it now (and cancel any pending re-conceal).
        case reveal
        /// It should hide but is already concealed — just cancel any pending re-conceal.
        case keepConcealed
        /// It should hide during a live (animated) pass — schedule the delayed re-conceal.
        case scheduleReConceal
        /// It should hide on an instant (non-animated) pass — conceal it at once.
        case concealNow
    }

    /// How a tab transitions given the current reveal decision, whether it is already
    /// concealed, and whether this is an animated (live) or instant pass. A tab that must
    /// hide waits out `reConcealDelay` only on animated passes; an instant pass (reconcile
    /// / launch) snaps it hidden immediately.
    static func revealTransition(reveal: Bool, isConcealed: Bool, animated: Bool) -> RevealTransition {
        if reveal { return .reveal }
        if isConcealed { return .keepConcealed }
        return animated ? .scheduleReConceal : .concealNow
    }
}
