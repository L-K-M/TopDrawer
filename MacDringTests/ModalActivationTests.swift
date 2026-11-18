#if os(macOS)
import XCTest
@testable import MacDring

final class ModalActivationTests: XCTestCase {
    func testHandsActivationBackOnlyToAnotherRunningApp() {
        let own: pid_t = 100
        XCTAssertTrue(ModalActivation.shouldHandBack(toPID: 200, isTerminated: false, ownPID: own))
        XCTAssertFalse(ModalActivation.shouldHandBack(toPID: own, isTerminated: false, ownPID: own),
                       "Settings had focus: Top Drawer keeps it")
        XCTAssertFalse(ModalActivation.shouldHandBack(toPID: 200, isTerminated: true, ownPID: own),
                       "The previous app quit while the prompt was up")
        XCTAssertFalse(ModalActivation.shouldHandBack(toPID: nil, isTerminated: false, ownPID: own),
                       "No app was frontmost")
    }
}
#endif
