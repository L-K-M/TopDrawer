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
    private let lock = NSLock()
    private var onCancel: (() -> Void)?
    init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func cancel() {
        // Swap the handler out under the lock and run it outside — the way
        // ObservableObjectPublisher.send() fires callbacks outside its lock — so two
        // racing cancels (or a cancel racing deinit) run the handler at most once.
        lock.lock()
        let handler = onCancel
        onCancel = nil
        lock.unlock()
        handler?()
    }
    deinit { cancel() }
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

// Each object's publisher lives in a box that keeps the object itself only *weakly*,
// keyed by `ObjectIdentifier`. Identifiers are unique among live objects, so a box
// whose `object === self` is genuinely ours; a stale box — its object deallocated and
// its address recycled into `self` — is replaced with a fresh publisher on the next
// access. That `=== self` check is load-bearing: a subscriber lives in its
// `AnyCancellable` (see below), not in the observable object, so a cancellable that
// outlives its object keeps that object's subscribers registered on the boxed
// publisher; without the check a new object at the recycled address would inherit the
// dead object's publisher and fire its subscribers on every `@Published` set. Replacing
// the box also drops the old publisher and its captured closures, close to how real
// Combine releases them with the object. (There is no `objc_setAssociatedObject` on
// Linux to hang per-instance storage off instead, so a dead object's box would linger
// until its address is reused — including any subscriber closures an outlived
// cancellable keeps registered — so the accessor sweeps dead boxes on each cache miss.)
private final class ObjectWillChangeBox {
    weak var object: AnyObject?
    let publisher: ObservableObjectPublisher
    init(object: AnyObject, publisher: ObservableObjectPublisher) {
        self.object = object
        self.publisher = publisher
    }
}

private let objectWillChangeRegistryLock = NSLock()
private var objectWillChangeRegistry: [ObjectIdentifier: ObjectWillChangeBox] = [:]

extension ObservableObject {
    var objectWillChange: ObservableObjectPublisher {
        let key = ObjectIdentifier(self)
        objectWillChangeRegistryLock.lock()
        defer { objectWillChangeRegistryLock.unlock() }
        if let box = objectWillChangeRegistry[key], box.object === self {
            return box.publisher
        }
        // Cache miss (once per object): sweep boxes whose weak object has deallocated, so
        // the registry can't grow without bound and an outlived cancellable's subscriber
        // closures are released with their object rather than pinned. `object` goes nil
        // only after full deallocation, so no live object's box is ever removed; a
        // publisher still strongly referenced elsewhere survives (the box drop just
        // stops the registry being its last owner).
        objectWillChangeRegistry = objectWillChangeRegistry.filter { $0.value.object != nil }
        let box = ObjectWillChangeBox(object: self, publisher: ObservableObjectPublisher())
        objectWillChangeRegistry[key] = box
        return box.publisher
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
