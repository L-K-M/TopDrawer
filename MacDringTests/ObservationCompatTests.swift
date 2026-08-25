#if !canImport(Combine)
import XCTest
@testable import MacDring

/// Pins the Linux-only Combine stand-in (`MacDring/Common/ObservationCompat.swift`).
/// macOS uses real Combine, so this whole file compiles to nothing there.
final class ObservationCompatTests: XCTestCase {

    private final class Model: ObservableObject {
        @Published var value: Int = 0
    }

    /// `objectWillChange` is the same publisher across accesses for one object (so a
    /// sink observes the sends `@Published` emits) and a distinct one per object.
    func testObjectWillChangeIsPerObjectStable() {
        let a = Model(), b = Model()
        XCTAssertTrue(a.objectWillChange === a.objectWillChange)
        XCTAssertFalse(a.objectWillChange === b.objectWillChange)
    }

    /// A `@Published` set publishes exactly once, and delivery stops after `cancel()`.
    func testPublishedSetPublishesOncePerSetAndStopsAfterCancel() {
        let model = Model()
        var count = 0
        // objectWillChange must fire *before* the value changes (willSet semantics, as in
        // real Combine): at each emission model.value is still the pre-change value, which
        // equals the number of sets seen so far (0 before the first set, 1 before the second).
        let cancellable = model.objectWillChange.sink {
            XCTAssertEqual(model.value, count, "objectWillChange must fire before the change")
            count += 1
        }
        withExtendedLifetime(cancellable) {
            model.value = 1
            model.value = 2
        }
        XCTAssertEqual(count, 2)

        cancellable.cancel()
        model.value = 3
        XCTAssertEqual(count, 2, "no delivery after cancel")
    }

    /// The registry must not let a new object inherit a dead object's publisher — the
    /// case that matters when a cancellable outlives its object (kept in a long-lived
    /// collection) and the freed object's address is later recycled. The retained
    /// subscriber below must never fire for `second`, and `second` must get its own
    /// publisher regardless of where it lands.
    func testNewObjectDoesNotInheritADeadObjectsPublisher() throws {
        var retainedCancellable: AnyCancellable?
        var deadPublisher: ObservableObjectPublisher?
        var firstAddress: UnsafeMutableRawPointer?
        do {
            let first = Model()
            firstAddress = Unmanaged.passUnretained(first).toOpaque()
            deadPublisher = first.objectWillChange
            retainedCancellable = first.objectWillChange.sink {
                XCTFail("a deallocated object's subscriber was fired by a different object")
            }
        }   // `first` is released here; `retainedCancellable` (and thus its subscriber) lives on.

        let second = Model()
        // The cross-talk this guards against only manifests when `second` lands on the
        // freed object's recycled address. Surface a run that didn't exercise that path
        // as a skip, so a vacuous pass can't masquerade as a real one.
        try XCTSkipIf(Unmanaged.passUnretained(second).toOpaque() != firstAddress,
                      "allocator did not recycle the dead object's address; recycled-address path not exercised")
        XCTAssertFalse(second.objectWillChange === deadPublisher,
                       "a new object must not resolve to a dead object's publisher")
        withExtendedLifetime(retainedCancellable) {
            second.value = 99   // must route to second's own (subscriber-free) publisher
        }
    }
}
#endif
