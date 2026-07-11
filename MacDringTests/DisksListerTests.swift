import XCTest
@testable import MacDring

final class DisksListerTests: XCTestCase {

    private func volume(_ name: String,
                        ejectable: Bool = false,
                        removable: Bool = false,
                        isInternal: Bool = false,
                        browsable: Bool = true) -> DisksLister.Volume {
        DisksLister.Volume(
            url: URL(fileURLWithPath: "/Volumes/\(name)", isDirectory: true),
            name: name,
            isEjectable: ejectable,
            isRemovable: removable,
            isInternal: isInternal,
            isBrowsable: browsable
        )
    }

    func testKeepsExternalRemovableEjectableAndNetworkVolumes() {
        let usb = volume("USB", ejectable: true)
        let sd = volume("SD", removable: true)
        let net = volume("Server")        // not internal → a network/external mount, kept
        let dmg = volume("Installer")      // not internal → a mounted disk image, kept
        let items = DisksLister.items(from: [usb, sd, net, dmg])
        XCTAssertEqual(items.count, 4)
        XCTAssertTrue(items.allSatisfy { $0.kind == .disk })
    }

    func testExcludesInternalStartupDisk() {
        let boot = volume("Macintosh HD", isInternal: true)   // fixed internal system volume
        let usb = volume("USB", ejectable: true)
        let items = DisksLister.items(from: [boot, usb])
        XCTAssertEqual(items.map(\.displayName), ["USB"])     // the boot disk is omitted
    }

    func testExcludesNonBrowsableVolumes() {
        let hidden = volume("VM", browsable: false)           // a hidden system volume
        XCTAssertTrue(DisksLister.items(from: [hidden]).isEmpty)
    }

    func testInternalButEjectableIsKept() {
        // An internal-bus drive that still reports itself ejectable (e.g. an
        // internal optical/card bay) should remain — eject still applies.
        XCTAssertTrue(DisksLister.isEjectable(volume("Bay", ejectable: true, isInternal: true)))
    }

    func testSortedCaseInsensitivelyWithSequentialSlots() {
        let items = DisksLister.items(from: [
            volume("Charlie", ejectable: true),
            volume("alpha", ejectable: true),
            volume("Bravo", ejectable: true),
        ])
        XCTAssertEqual(items.map(\.displayName), ["alpha", "Bravo", "Charlie"])
        XCTAssertEqual(items.map(\.slot), [0, 1, 2])
    }

    func testItemsCarryVolumeURL() throws {
        let v = volume("USB", ejectable: true)
        let item = try XCTUnwrap(DisksLister.items(from: [v]).first)
        XCTAssertEqual(item.url, v.url)
        XCTAssertEqual(BookmarkResolver.url(for: item), v.url)   // resolves to the volume root
    }

    func testNonDisksTabReturnsEmpty() {
        let tab = Tab(title: "I", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5),
                      kind: .items)
        XCTAssertTrue(DisksLister.contents(of: tab).isEmpty)
    }
}
