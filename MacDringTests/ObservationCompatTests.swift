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
        let cancellable = model.objectWillChange.sink { count += 1 }
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
    func testNewObjectDoesNotInheritADeadObjectsPublisher() {
        var retainedCancellable: AnyCancellable?
        var deadPublisher: ObservableObjectPublisher?
        do {
            let first = Model()
            deadPublisher = first.objectWillChange
            retainedCancellable = first.objectWillChange.sink {
                XCTFail("a deallocated object's subscriber was fired by a different object")
            }
        }   // `first` is released here; `retainedCancellable` (and thus its subscriber) lives on.

        let second = Model()
        XCTAssertFalse(second.objectWillChange === deadPublisher,
                       "a new object must not resolve to a dead object's publisher")
        withExtendedLifetime(retainedCancellable) {
            second.value = 99   // must route to second's own (subscriber-free) publisher
        }
    }
}
#endif
