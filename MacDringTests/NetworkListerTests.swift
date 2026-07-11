import XCTest
@testable import MacDring

final class NetworkListerTests: XCTestCase {

    private func volume(_ name: String,
                        isLocal: Bool = false,
                        browsable: Bool = true) -> NetworkLister.Volume {
        NetworkLister.Volume(
            url: URL(fileURLWithPath: "/Volumes/\(name)", isDirectory: true),
            name: name,
            isLocal: isLocal,
            isBrowsable: browsable
        )
    }

    func testKeepsRemoteBrowsableVolumesOnly() {
        let share = volume("Server")                       // remote (not local) → kept
        let local = volume("Macintosh HD", isLocal: true)  // a local disk → excluded
        let usb = volume("USB", isLocal: true)             // local removable → excluded (Disks tab's job)
        let hidden = volume("vm", browsable: false)        // hidden system mount → excluded
        let items = NetworkLister.items(from: [share, local, usb, hidden])
        XCTAssertEqual(items.map(\.displayName), ["Server"])
        XCTAssertEqual(items.first?.kind, .disk)            // shares are ejectable .disk items
    }

    func testIsNetworkPredicate() {
        XCTAssertTrue(NetworkLister.isNetwork(volume("Share")))                 // remote, browsable
        XCTAssertFalse(NetworkLister.isNetwork(volume("Disk", isLocal: true)))  // local
        XCTAssertFalse(NetworkLister.isNetwork(volume("Hidden", browsable: false)))
    }

    func testSortedCaseInsensitivelyWithSequentialSlots() {
        let items = NetworkLister.items(from: [volume("Zeta"), volume("alpha"), volume("Mike")])
        XCTAssertEqual(items.map(\.displayName), ["alpha", "Mike", "Zeta"])
        XCTAssertEqual(items.map(\.slot), [0, 1, 2])
    }

    func testItemsCarryURLThatResolves() throws {
        let share = volume("Server")
        let item = try XCTUnwrap(NetworkLister.items(from: [share]).first)
        XCTAssertEqual(item.url, share.url)
        XCTAssertEqual(BookmarkResolver.url(for: item), share.url)
    }

    func testNonNetworkTabReturnsEmpty() {
        let tab = Tab(title: "I", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5),
                      kind: .items)
        XCTAssertTrue(NetworkLister.contents(of: tab).isEmpty)
    }
}
