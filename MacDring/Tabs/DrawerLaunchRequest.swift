import Foundation

/// Identifies one launch from one specific opening of a drawer. A later launch in
/// the same drawer, or closing and reopening that drawer, prevents this request from
/// changing the current drawer; it does not gate Recents recording.
struct DrawerLaunchRequest: Equatable {
    let requestID: UUID
    let tabID: UUID
    let sessionID: UUID

    init(requestID: UUID = UUID(), tabID: UUID, sessionID: UUID) {
        self.requestID = requestID
        self.tabID = tabID
        self.sessionID = sessionID
    }

    func canUpdateDrawer(openTabID: UUID?, sessionID: UUID?, requestID: UUID?) -> Bool {
        tabID == openTabID && self.sessionID == sessionID && self.requestID == requestID
    }
}
