import XCTest
import AppKit
@testable import MacDring

final class IconStyleTests: XCTestCase {

    // MARK: IconStyle Codable

    func testCodableRoundTrip() throws {
        let style = IconStyle(base: .tile, colorHex: "#FF8800", symbol: "star.fill")
        let data = try JSONEncoder().encode(style)
        XCTAssertEqual(try JSONDecoder().decode(IconStyle.self, from: data), style)
    }

    func testDecodeDefaultsForwardCompatible() throws {
        let decoded = try JSONDecoder().decode(IconStyle.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.base, .folder)
        XCTAssertEqual(decoded.colorHex, "#0A84FF")
        XCTAssertNil(decoded.symbol)
    }

    func testDecodeUnknownBaseFallsBackWithoutDroppingStyle() throws {
        let json = """
        { "base": "futureShape", "colorHex": "#112233", "symbol": "star.fill" }
        """

        let decoded = try JSONDecoder().decode(IconStyle.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.base, .folder)
        XCTAssertEqual(decoded.colorHex, "#112233")
        XCTAssertEqual(decoded.symbol, "star.fill")
    }

    // MARK: applyingIconStyles (live items keyed by path)

    func testApplyingIconStylesKeysByPath() {
        let server = URL(fileURLWithPath: "/Volumes/Server", isDirectory: true)
        let usb = URL(fileURLWithPath: "/Volumes/USB", isDirectory: true)
        let items = [
            DrawerItem(kind: .disk, displayName: "Server", url: server, slot: 0),
            DrawerItem(kind: .disk, displayName: "USB", url: usb, slot: 1),
        ]
        let style = IconStyle(base: .tile, colorHex: "#112233", symbol: "network")
        let result = items.applyingIconStyles(from: [server.path: style])
        XCTAssertEqual(result[0].iconStyle, style)   // matched by path
        XCTAssertNil(result[1].iconStyle)            // no override → unchanged
    }

    func testApplyingIconStylesEmptyIsNoOp() {
        let item = DrawerItem(kind: .folder, displayName: "X",
                              url: URL(fileURLWithPath: "/x", isDirectory: true), slot: 0)
        XCTAssertEqual([item].applyingIconStyles(from: [:]), [item])
    }

    // MARK: DrawerItem carries iconStyle through Codable

    func testDrawerItemEncodesIconStyle() throws {
        var item = DrawerItem(kind: .file, displayName: "F", url: URL(fileURLWithPath: "/f"), slot: 0)
        item.iconStyle = IconStyle(base: .folder, colorHex: "#00FF00", symbol: nil)
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(DrawerItem.self, from: data).iconStyle, item.iconStyle)
    }

    // MARK: IconRenderer produces a drawable image of the requested size

    func testRendererProducesSizedDrawableImage() {
        let folder = IconRenderer.image(
            for: IconStyle(base: .folder, colorHex: "#0A84FF", symbol: "star.fill"), pointSize: 64)
        XCTAssertEqual(folder.size, NSSize(width: 64, height: 64))
        XCTAssertNotNil(folder.tiffRepresentation)   // forces the draw — catches drawing crashes

        let tile = IconRenderer.image(
            for: IconStyle(base: .tile, colorHex: "#FFFFFF", symbol: nil), pointSize: 64)
        XCTAssertEqual(tile.size, NSSize(width: 64, height: 64))
        XCTAssertNotNil(tile.tiffRepresentation)
    }
}
