import Foundation

/// Serialises work onto one private queue, and runs it inline when the caller is
/// already on that queue.
///
/// `DispatchQueue.sync` onto the queue you are already on traps ("dispatch_sync
/// called on the same queue"), and that is reachable from ordinary teardown
/// rather than being a theoretical mistake: a queued closure that releases the
/// last reference to an object makes that object's `deinit` run *on the queue*,
/// and any `stop()`-style cleanup it performs then needs the same mutual
/// exclusion an outside caller gets. `INotifyWatcher` is exactly that shape —
/// its read handler and retry closure can both be the last owner — and it used
/// to trap here, which surfaced as an intermittent crash in the daemon tests.
///
/// The rule this encodes: a type that both serialises its state and can be
/// deallocated from inside that serialisation must not assume `sync` comes from
/// outside.
final class SerialQueueGate {

    /// The underlying queue, for the one thing that needs a queue rather than a
    /// closure: constructing a `DispatchSource` that delivers onto it.
    ///
    /// Do not call `sync` or `async` on this directly — go through `sync`/`async`
    /// below, or you reintroduce the trap this type exists to prevent.
    let queue: DispatchQueue

    private let key = DispatchSpecificKey<Void>()

    init(label: String, qos: DispatchQoS = .utility) {
        queue = DispatchQueue(label: label, qos: qos)
        // Tagging the queue is what makes re-entrancy detectable; the value is
        // irrelevant, only its presence.
        queue.setSpecific(key: key, value: ())
    }

    /// Whether the caller is already executing on this gate's queue.
    var isOnQueue: Bool { DispatchQueue.getSpecific(key: key) != nil }

    /// Runs `body` on the queue, or inline when the caller is already there.
    func sync(_ body: () -> Void) {
        if isOnQueue {
            body()
        } else {
            queue.sync(execute: body)
        }
    }

    /// Runs `body` on the queue after `delay` seconds (0 to just enqueue it).
    func async(after delay: TimeInterval = 0, _ body: @escaping () -> Void) {
        queue.asyncAfter(deadline: .now() + delay, execute: body)
    }
}
