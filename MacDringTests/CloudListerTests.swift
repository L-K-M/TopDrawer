import XCTest
@testable import MacDring

final class CloudListerTests: XCTestCase {

    private func cloud(_ name: String) -> CloudLister.CloudRoot {
        CloudLister.CloudRoot(
            url: URL(fileURLWithPath: "/Users/me/Library/CloudStorage/\(name)", isDirectory: true),
            name: name
        )
    }

    func testCloudRootsBecomeCloudItemsSortedWithSlots() {
        let items = CloudLister.items(from: [cloud("OneDrive"), cloud("Box"), cloud("Dropbox")])
        XCTAssertEqual(items.map(\.displayName), ["Box", "Dropbox", "OneDrive"])
        XCTAssertEqual(items.map(\.slot), [0, 1, 2])
        XCTAssertTrue(items.allSatisfy { $0.kind == .cloud })   // openable cloud items
    }

    func testItemsCarryURLThatResolves() throws {
        let root = cloud("Dropbox")
        let item = try XCTUnwrap(CloudLister.items(from: [root]).first)
        XCTAssertEqual(item.url, root.url)
        XCTAssertEqual(BookmarkResolver.url(for: item), root.url)
    }

    func testNonCloudTabReturnsEmpty() {
        let tab = Tab(title: "N", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5),
                      kind: .network)
        XCTAssertTrue(CloudLister.contents(of: tab).isEmpty)
    }

    func testCloudRootsReadFromInjectedHome() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = home.appendingPathComponent("Library/CloudStorage/Dropbox", isDirectory: true)
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        try fm.createDirectory(at: provider, withIntermediateDirectories: true)
        try fm.createDirectory(at: iCloud, withIntermediateDirectories: true)
        // A stray file under CloudStorage must be ignored (only directories are roots).
        try Data().write(to: home.appendingPathComponent("Library/CloudStorage/notes.txt"))
        defer { try? fm.removeItem(at: home) }

        let roots = CloudLister.cloudRoots(home: home)
        XCTAssertEqual(Set(roots.map(\.name)), ["iCloud Drive", "Dropbox"])
    }

    func testProviderIconStyleMapsKnownProviders() {
        XCTAssertEqual(CloudLister.providerIconStyle(forName: "iCloud Drive")?.colorHex, "#3B9EFF")
        XCTAssertEqual(CloudLister.providerIconStyle(forName: "Dropbox")?.colorHex, "#0061FF")
        XCTAssertEqual(CloudLister.providerIconStyle(forName: "Google Drive")?.colorHex, "#1FA463")
        XCTAssertEqual(CloudLister.providerIconStyle(forName: "OneDrive")?.colorHex, "#0078D4")
        XCTAssertEqual(CloudLister.providerIconStyle(forName: "Box")?.colorHex, "#0061D5")
        // "Dropbox" contains "box" but must resolve to Dropbox, not Box (order matters).
        XCTAssertEqual(CloudLister.providerIconStyle(forName: "Dropbox")?.symbol, "shippingbox.fill")
        // Unknown provider keeps the generic cloud icon (nil style).
        XCTAssertNil(CloudLister.providerIconStyle(forName: "Mystery Cloud"))
        // A provider merely *named* "* Drive" must not get Google's branding.
        XCTAssertNil(CloudLister.providerIconStyle(forName: "Proton Drive"))
        XCTAssertNil(CloudLister.providerIconStyle(forName: "pCloud Drive"))
    }

    func testProviderIconStyleAttachedToItems() {
        let items = CloudLister.items(from: [
            CloudLister.CloudRoot(url: URL(fileURLWithPath: "/x/Dropbox"), name: "Dropbox"),
            CloudLister.CloudRoot(url: URL(fileURLWithPath: "/x/Mystery"), name: "Mystery"),
        ])
        XCTAssertEqual(items.first(where: { $0.displayName == "Dropbox" })?.iconStyle?.colorHex, "#0061FF")
        XCTAssertNil(items.first(where: { $0.displayName == "Mystery" })?.iconStyle)
    }
}
