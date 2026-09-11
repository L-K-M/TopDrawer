import XCTest
@testable import MacDring

/// `SerialQueueGate` exists because a queued closure can release the last
/// reference to the object that owns the queue, so `deinit` runs on the queue and
/// any `stop()`-style cleanup it calls would trap in `DispatchQueue.sync`. These
/// tests pin the rule directly: `sync` is re-entrant, and `isOnQueue` tells the
/// truth from both sides.
final class SerialQueueGateTests: XCTestCase {

    func testSyncRunsBodyOnTheQueue() {
        let gate = SerialQueueGate(label: "test.gate.on-queue")
        var ranOnQueue = false
        gate.sync { ranOnQueue = gate.isOnQueue }
        XCTAssertTrue(ranOnQueue)
    }

    func testIsOnQueueIsFalseOffTheQueue() {
        let gate = SerialQueueGate(label: "test.gate.off-queue")
        XCTAssertFalse(gate.isOnQueue)
    }

    /// The regression this type was written for: a nested `sync` used to reach
    /// `DispatchQueue.sync` on the current queue, which is a runtime trap rather
    /// than an error.
    func testSyncIsReentrant() {
        let gate = SerialQueueGate(label: "test.gate.reentrant")
        var inner = false
        gate.sync {
            gate.sync {
                inner = gate.isOnQueue
            }
        }
        XCTAssertTrue(inner, "a nested sync must run inline instead of trapping")
    }

    func testAsyncRunsOnTheQueue() {
        let gate = SerialQueueGate(label: "test.gate.async")
        let expectation = expectation(description: "async body ran")
        gate.async(after: 0) {
            XCTAssertTrue(gate.isOnQueue)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        XCTAssertFalse(gate.isOnQueue, "the main test thread is not on the gate")
    }

    /// `sync` must actually serialise: a body running on the queue cannot be
    /// interleaved with a second one, so the flag never observes a partial state.
    func testSyncSerialisesConcurrentCallers() {
        let gate = SerialQueueGate(label: "test.gate.serial")
        let iterations = 200
        var counter = 0

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            gate.sync { counter += 1 }
        }

        XCTAssertEqual(counter, iterations)
    }
}
