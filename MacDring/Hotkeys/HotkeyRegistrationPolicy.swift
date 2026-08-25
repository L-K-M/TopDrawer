import Foundation

/// Pure global-hotkey conflict resolution lifted out of `TabController` (LP-11): given
/// a tab's desired spec, its current registration, the per-session failure cache, and
/// whether another Top Drawer tab already owns the spec, it decides *what the controller
/// should do* — drop, keep, skip, defer, or (re)register. The Carbon calls and the cache
/// mutations stay in the controller; this is the branch logic only, so it's fully
/// unit-testable on both platforms. See PLAN.md §10.
enum HotkeyRegistrationPolicy {

    /// What to do about a tab's hotkey registration this reconcile pass. The controller
    /// executes the Carbon/cache side effects; the `releaseStale…` cases mean the tab
    /// currently holds a registration under a *different* spec that must be unregistered
    /// first (which also clears its cached failure).
    enum Decision: Equatable {
        /// No usable spec — release any registration this tab holds. Not blocked.
        case unregister
        /// Already registered with exactly this spec — nothing to do.
        case keepExisting
        /// This spec failed a Carbon registration earlier this session and hasn't
        /// changed — stay failed; don't retry or re-log. (Only when no live
        /// registration exists, since releasing a stale one clears the cache.)
        case skipCachedFailure
        /// The tab's spec changed and another live Top Drawer tab owns the new spec:
        /// release the stale registration, then report the tab as blocked so the bounded
        /// second pass retries once the owner releases or changes.
        case releaseStaleThenDefer
        /// No live registration and another Top Drawer tab owns the spec: report the tab
        /// as blocked (don't cache — the bounded pass must be free to retry).
        case deferToOwner
        /// The tab's spec changed and the new spec is free: release the stale
        /// registration, then ask Carbon to register.
        case releaseStaleThenRegister
        /// No live registration and the spec is free (and not a cached failure): ask
        /// Carbon to register.
        case register
    }

    /// Whether the decision reports the tab as **blocked** — i.e. another Top Drawer tab
    /// owns the spec, so the caller includes it in the bounded second registration pass.
    static func isBlocked(_ decision: Decision) -> Bool {
        decision == .releaseStaleThenDefer || decision == .deferToOwner
    }

    /// Decide what to do with `spec` for a tab, given:
    /// - `usable`: whether `spec` is a registerable hotkey (`KeyCodes.isUsableHotkey`);
    /// - `existing`: the spec this tab is currently registered under, if any;
    /// - `cachedFailure`: the spec this tab last failed to register this session, if any;
    /// - `ownedByOtherTab`: whether a *different* live Top Drawer tab holds `spec`.
    ///
    /// Mirrors `registerHotkeyIfNeeded`'s branch order: an unchanged live registration
    /// wins first; a changed spec releases the stale one before it is re-evaluated (so a
    /// cached failure can only apply when there is no live registration); a conflict Top
    /// Drawer already owns is deferred rather than handed to Carbon.
    static func decide(spec: HotkeySpec?, usable: Bool, existing: HotkeySpec?,
                       cachedFailure: HotkeySpec?, ownedByOtherTab: Bool) -> Decision {
        guard let spec, usable else { return .unregister }
        if let existing {
            if existing == spec { return .keepExisting }
            return ownedByOtherTab ? .releaseStaleThenDefer : .releaseStaleThenRegister
        }
        if cachedFailure == spec { return .skipCachedFailure }
        return ownedByOtherTab ? .deferToOwner : .register
    }
}
