#if !canImport(Combine)
import Foundation

// A minimal stand-in for the sliver of Combine the shared observable models use, so
// they compile and their tests run on Linux (which has no Combine). macOS keeps the
// real Combine — this file is compiled only where Combine is absent — so the shipping
// app is untouched. Fidelity is deliberately limited to what the ported code and its
// tests exercise: `ObservableObject` + `@Published` + `objectWillChange.send()/.sink`.
// See docs/linux-port/implementation-plan.md §LP-07.
//
// The types are named to match Combine's so the shared code (`TabStore`, `Preferences`,
// …) reads identically on both platforms; they live in the `MacDring` module rather
// than a module called `Combine`, which is why the bare `import Combine` lines are
// wrapped in `#if canImport(Combine)`.

/// Cancels a subscription when cancelled or deinited — enough of Combine's
/// `AnyCancellable` for the `let c = ….sink { … }` pattern the tests use.
final class AnyCancellable {
    private var onCancel: (() -> Void)?
    init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func cancel() { onCancel?(); onCancel = nil }
    deinit { onCancel?() }
}

/// The publisher `objectWillChange` vends. `send()` notifies every live subscriber;
/// `sink` registers one and returns a cancellable that removes it. Thread-safe so a
/// send and a cancel can race the way they do under Combine.
final class ObservableObjectPublisher {
    private let lock = NSLock()
    private var subscribers: [UUID: () -> Void] = [:]

    init() {}

    func send() {
        lock.lock()
        let callbacks = Array(subscribers.values)
        lock.unlock()
        // Fire outside the lock: a subscriber that cancels (or sends) re-enters here.
        for callback in callbacks { callback() }
    }

    func sink(receiveValue: @escaping () -> Void) -> AnyCancellable {
        let id = UUID()
        lock.lock()
        subscribers[id] = receiveValue
        lock.unlock()
        return AnyCancellable { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.subscribers[id] = nil
            self.lock.unlock()
        }
    }
}

/// Combine's `ObservableObject`. The default `objectWillChange` must be
/// **per-object-stable** — a fresh publisher per access would make
/// `objectWillChange.sink { }` observe none of the sends `@Published` emits — so it is
/// backed by a registry keyed on object identity.
protocol ObservableObject: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
}

// The registry holds each object's publisher strongly (nothing else does), keyed by
// `ObjectIdentifier`. It never evicts, so it leaks one small publisher per
// ObservableObject instance ever created — acceptable here because this shim only
// runs on Linux, where these models are exercised by a bounded set of tests and there
// is no `objc_setAssociatedObject` to hang per-instance storage off instead. An
// identifier is only reused after its object is freed (its subscribers gone with it),
// so a later object at the same address consistently resolves to the same entry with
// no cross-talk.
private let objectWillChangeRegistryLock = NSLock()
private var objectWillChangeRegistry: [ObjectIdentifier: ObservableObjectPublisher] = [:]

extension ObservableObject {
    var objectWillChange: ObservableObjectPublisher {
        let key = ObjectIdentifier(self)
        objectWillChangeRegistryLock.lock()
        defer { objectWillChangeRegistryLock.unlock() }
        if let existing = objectWillChangeRegistry[key] { return existing }
        let publisher = ObservableObjectPublisher()
        objectWillChangeRegistry[key] = publisher
        return publisher
    }
}

/// Combine's `@Published`. On set it fires the enclosing object's `objectWillChange`
/// *before* storing the new value — the ordering `objectWillChange` promises — which
/// it reaches via the `static subscript(_enclosingInstance:wrapped:storage:)`
/// property-wrapper feature (the same mechanism real Combine uses, and available on
/// Linux). `wrappedValue` is unavailable so a misuse on a non-`ObservableObject`
/// (which would silently never publish) is a compile error instead.
@propertyWrapper
struct Published<Value> {
    private var storedValue: Value

    init(wrappedValue: Value) { self.storedValue = wrappedValue }

    @available(*, unavailable,
               message: "@Published is only usable on a property of an ObservableObject class")
    var wrappedValue: Value {
        get { fatalError("@Published.wrappedValue is unavailable; use it on an ObservableObject") }
        set { fatalError("@Published.wrappedValue is unavailable; use it on an ObservableObject") }
    }

    static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance instance: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>
    ) -> Value {
        get { instance[keyPath: storageKeyPath].storedValue }
        set {
            instance.objectWillChange.send()
            instance[keyPath: storageKeyPath].storedValue = newValue
        }
    }
}
#endif
