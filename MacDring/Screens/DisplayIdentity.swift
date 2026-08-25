import Foundation

/// The stable display-identity seam (LP-13) `DisplayRegistry` provides: the persistent
/// UUID string for a screen, the currently-connected screen for a stored UUID, and a
/// change notification. `Screen` is the platform's screen handle — `NSScreen` on macOS
/// (`DisplayRegistry`), an opaque id + frame value type on a future Linux backend — so
/// the UUID that anchors a tab stays platform-neutral while the handle does not.
/// See PLAN.md §6, §LP-13.
protocol DisplayIdentity: AnyObject {
    associatedtype Screen

    /// Called on the main thread when displays are added, removed, or reconfigured.
    var onChange: (() -> Void)? { get set }

    /// The stable UUID string for a screen, or `nil` if it can't be determined.
    func uuid(for screen: Screen) -> String?

    /// The currently-connected screen for a stored UUID, or `nil` if that display isn't
    /// attached right now.
    func screen(for uuid: String) -> Screen?
}
