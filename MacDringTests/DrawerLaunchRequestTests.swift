import XCTest
@testable import Top Drawer

final class DrawerLaunchRequestTests: XCTestCase {

    func testCurrentRequestCanUpdateItsOriginatingDrawer() {
        let tabID = UUID()
        let sessionID = UUID()
        let requestID = UUID()
        let request = DrawerLaunchRequest(requestID: requestID, tabID: tabID, sessionID: sessionID)

        XCTAssertTrue(request.canUpdateDrawer(openTabID: tabID, sessionID: sessionID, requestID: requestID))
        XCTAssertFalse(request.canUpdateDrawer(openTabID: nil, sessionID: nil, requestID: nil))
        XCTAssertFalse(request.canUpdateDrawer(openTabID: UUID(), sessionID: sessionID, requestID: requestID))
    }

    func testReopeningSameTabPreventsEarlierRequestFromUpdatingDrawer() {
        let tabID = UUID()
        let requestID = UUID()
        let request = DrawerLaunchRequest(requestID: requestID, tabID: tabID, sessionID: UUID())

        XCTAssertFalse(request.canUpdateDrawer(openTabID: tabID, sessionID: UUID(), requestID: requestID))
    }

    func testNewLaunchInSameSessionPreventsEarlierRequestFromUpdatingDrawer() {
        let tabID = UUID()
        let sessionID = UUID()
        let request = DrawerLaunchRequest(requestID: UUID(), tabID: tabID, sessionID: sessionID)

        XCTAssertFalse(request.canUpdateDrawer(openTabID: tabID, sessionID: sessionID, requestID: UUID()))
    }
}
