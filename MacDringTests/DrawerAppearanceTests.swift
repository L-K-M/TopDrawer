import XCTest
@testable import MacDring

final class DrawerAppearanceTests: XCTestCase {

    private func decode(_ json: String,
                        floats: JSONDecoder.NonConformingFloatDecodingStrategy? = nil) throws -> DrawerAppearance {
        let decoder = JSONDecoder()
        if let floats { decoder.nonConformingFloatDecodingStrategy = floats }
        return try decoder.decode(DrawerAppearance.self, from: Data(json.utf8))
    }

    private func fileItem(_ displayName: String, _ path: String) -> DrawerItem {
        DrawerItem(kind: .file, displayName: displayName, url: URL(fileURLWithPath: path))
    }

    // MARK: Defaults & constants

    func testDefaults() {
        let appearance = DrawerAppearance()
        XCTAssertEqual(appearance.titleVisibility, .always)
        XCTAssertEqual(appearance.itemFontSize, 12)
        XCTAssertEqual(appearance.itemFontWeight, .regular)
        XCTAssertEqual(appearance.tabFontSize, 12)
        XCTAssertEqual(appearance.tabFontWeight, .semibold)
        XCTAssertEqual(appearance.fileExtensions, .system)
        XCTAssertEqual(appearance.preset, .system)
        XCTAssertEqual(appearance, .default)
    }

    func testDescriptiveConstantsMatchDefaultsAndLimits() {
        // UI (sliders, pickers) and tests read these instead of literals.
        XCTAssertEqual(DrawerAppearance.fontSizeRange, 10.0...20.0)
        XCTAssertEqual(DrawerAppearance.Default.titleVisibility, .always)
        XCTAssertEqual(DrawerAppearance.Default.itemFontSize, 12)
        XCTAssertEqual(DrawerAppearance.Default.itemFontWeight, .regular)
        XCTAssertEqual(DrawerAppearance.Default.tabFontSize, 12)
        XCTAssertEqual(DrawerAppearance.Default.tabFontWeight, .semibold)
        XCTAssertEqual(DrawerAppearance.Default.fileExtensions, .system)
        XCTAssertEqual(DrawerAppearance.Default.preset, .system)
        // Defaults are valid values: inside the range they promise.
        XCTAssertTrue(DrawerAppearance.fontSizeRange.contains(DrawerAppearance.Default.itemFontSize))
        XCTAssertTrue(DrawerAppearance.fontSizeRange.contains(DrawerAppearance.Default.tabFontSize))
    }

    func testEnumCasesHaveUniqueIDsRawValuesAndDisplayNames() {
        func check<T: RawRepresentable & CaseIterable & Identifiable>(_ type: T.Type,
                                                                      file: StaticString = #filePath,
                                                                      line: UInt = #line) where T.RawValue == String, T.ID == T {
            XCTAssertEqual(Set(type.allCases.map(\.rawValue)).count, type.allCases.count,
                           "duplicate raw values in \(type)", file: file, line: line)
            XCTAssertEqual(Set(type.allCases.map(\.id)).count, type.allCases.count,
                           "duplicate ids in \(type)", file: file, line: line)
            for c in type.allCases {
                XCTAssertEqual(c.id, c, file: file, line: line)
            }
        }
        check(DrawerAppearance.TitleVisibility.self)
        check(DrawerAppearance.FontWeight.self)
        check(DrawerAppearance.FileExtensions.self)
        check(DrawerAppearance.Preset.self)

        XCTAssertFalse(DrawerAppearance.TitleVisibility.allCases.map(\.displayName).contains(""))
        XCTAssertFalse(DrawerAppearance.FontWeight.allCases.map(\.displayName).contains(""))
        XCTAssertFalse(DrawerAppearance.FileExtensions.allCases.map(\.displayName).contains(""))
        XCTAssertFalse(DrawerAppearance.Preset.allCases.map(\.displayName).contains(""))
    }

    // MARK: Codable

    func testCodableRoundTrip() throws {
        let appearance = DrawerAppearance(titleVisibility: .onHover,
                                          itemFontSize: 14.5,
                                          itemFontWeight: .bold,
                                          tabFontSize: 11,
                                          tabFontWeight: .medium,
                                          fileExtensions: .hide,
                                          preset: .glass)
        let data = try JSONEncoder().encode(appearance)
        XCTAssertEqual(try JSONDecoder().decode(DrawerAppearance.self, from: data), appearance)
    }

    func testEncodedShapeIsFlatFieldKeys() throws {
        // Tab persists this inside launcher.json; the field names are the wire format.
        let data = try JSONEncoder().encode(DrawerAppearance())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys),
                       ["titleVisibility", "itemFontSize", "itemFontWeight",
                        "tabFontSize", "tabFontWeight", "fileExtensions", "preset"])
        XCTAssertEqual(object["titleVisibility"] as? String, "always")
        XCTAssertEqual(object["preset"] as? String, "system")
    }

    func testDecodeMissingFieldsYieldsDefaults() throws {
        XCTAssertEqual(try decode("{}"), DrawerAppearance())
    }

    func testUnknownEnumRawValuesFallBackPerField() throws {
        // Raw values a newer Top Drawer may write degrade field-by-field; valid
        // siblings (and plain fields) survive.
        let json = """
        { "titleVisibility": "onShake", "itemFontWeight": "ultra", "tabFontWeight": "wispy",
          "fileExtensions": "sometimes", "preset": "neon", "itemFontSize": 16, "tabFontSize": 11 }
        """
        let appearance = try decode(json)
        XCTAssertEqual(appearance.titleVisibility, .always)
        XCTAssertEqual(appearance.itemFontWeight, .regular)
        XCTAssertEqual(appearance.tabFontWeight, .semibold)
        XCTAssertEqual(appearance.fileExtensions, .system)
        XCTAssertEqual(appearance.preset, .system)
        XCTAssertEqual(appearance.itemFontSize, 16)
        XCTAssertEqual(appearance.tabFontSize, 11)
    }

    func testMalformedFieldTypesFallBackKeepingValidSiblings() throws {
        let json = """
        { "itemFontSize": "big", "tabFontSize": {"points": 14}, "preset": 7,
          "titleVisibility": "onHover", "fileExtensions": "hide" }
        """
        let appearance = try decode(json)
        XCTAssertEqual(appearance.itemFontSize, 12)
        XCTAssertEqual(appearance.tabFontSize, 12)
        XCTAssertEqual(appearance.preset, .system)
        XCTAssertEqual(appearance.titleVisibility, .onHover)
        XCTAssertEqual(appearance.fileExtensions, .hide)
    }

    func testPartiallyMalformedAppearanceStillDecodesInsideTab() throws {
        // The real stake of per-field leniency: one bad field must not cost the
        // whole tab on the next launcher.json autosave.
        let json = """
        { "title": "T",
          "anchor": { "displayUUID": "uuid-1", "edge": "right", "position": 0.5, "order": 0 },
          "appearance": { "preset": "glass", "itemFontSize": "oops" } }
        """
        let tab = try JSONDecoder().decode(Tab.self, from: Data(json.utf8))
        XCTAssertEqual(tab.title, "T")
        XCTAssertEqual(tab.appearance.preset, .glass)
        XCTAssertEqual(tab.appearance.itemFontSize, 12)
    }

    // MARK: Size clamping

    func testInitClampsOutOfRangeSizes() {
        let appearance = DrawerAppearance(itemFontSize: 4, tabFontSize: 42)
        XCTAssertEqual(appearance.itemFontSize, 10)
        XCTAssertEqual(appearance.tabFontSize, 20)

        let bounds = DrawerAppearance(itemFontSize: 10, tabFontSize: 20)
        XCTAssertEqual(bounds.itemFontSize, 10)
        XCTAssertEqual(bounds.tabFontSize, 20)
    }

    func testInitFallsBackToDefaultForNonFiniteSizes() {
        for value in [Double.nan, .infinity, -.infinity] {
            let appearance = DrawerAppearance(itemFontSize: value, tabFontSize: value)
            XCTAssertEqual(appearance.itemFontSize, 12)
            XCTAssertEqual(appearance.tabFontSize, 12)
        }
    }

    func testAssignmentClampsAndFallsBack() {
        var appearance = DrawerAppearance()
        appearance.itemFontSize = 6
        XCTAssertEqual(appearance.itemFontSize, 10)
        appearance.itemFontSize = 99
        XCTAssertEqual(appearance.itemFontSize, 20)
        appearance.itemFontSize = 14
        XCTAssertEqual(appearance.itemFontSize, 14)
        appearance.itemFontSize = .nan
        XCTAssertEqual(appearance.itemFontSize, 12)
        appearance.tabFontSize = .infinity
        XCTAssertEqual(appearance.tabFontSize, 12)
        appearance.tabFontSize = -.infinity
        XCTAssertEqual(appearance.tabFontSize, 12)
    }

    func testDecodeClampsOutOfRangeSizes() throws {
        let appearance = try decode(#"{"itemFontSize": 2, "tabFontSize": 99}"#)
        XCTAssertEqual(appearance.itemFontSize, 10)
        XCTAssertEqual(appearance.tabFontSize, 20)
    }

    func testDecodeNonFiniteSizesFallBackToDefaults() throws {
        // JSON can't spell NaN/inf, but non-conforming decoders can produce them.
        let floats = JSONDecoder.NonConformingFloatDecodingStrategy.convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let appearance = try decode(#"{"itemFontSize": "NaN", "tabFontSize": "Infinity"}"#, floats: floats)
        XCTAssertEqual(appearance.itemFontSize, 12)
        XCTAssertEqual(appearance.tabFontSize, 12)
    }

    // MARK: title(for:) — .system / .show / .hide

    func testSystemPreservesStoredName() {
        let appearance = DrawerAppearance(fileExtensions: .system)
        XCTAssertEqual(appearance.title(for: fileItem("report", "/tmp/report.pdf")), "report")
        XCTAssertEqual(appearance.title(for: fileItem("report.pdf", "/tmp/report.pdf")), "report.pdf")
    }

    func testShowAddsTheActualExtensionWhenAbsent() {
        let appearance = DrawerAppearance(fileExtensions: .show)
        XCTAssertEqual(appearance.title(for: fileItem("report", "/tmp/report.pdf")), "report.pdf")
        XCTAssertEqual(appearance.title(for: fileItem("report.pdf", "/tmp/report.pdf")), "report.pdf")
        // Nothing to add for an extensionless file.
        XCTAssertEqual(appearance.title(for: fileItem("Makefile", "/tmp/Makefile")), "Makefile")
    }

    func testHideRemovesOnlyTheActualLastExtension() {
        let appearance = DrawerAppearance(fileExtensions: .hide)
        XCTAssertEqual(appearance.title(for: fileItem("report.pdf", "/tmp/report.pdf")), "report")
        // Dotted names lose one suffix at a time, never all of them.
        XCTAssertEqual(appearance.title(for: fileItem("archive.tar.gz", "/tmp/archive.tar.gz")), "archive.tar")
        XCTAssertEqual(appearance.title(for: fileItem("name.with.dots.txt", "/tmp/name.with.dots.txt")), "name.with.dots")
        // Already-base names stay; nothing is stripped twice or invented.
        XCTAssertEqual(appearance.title(for: fileItem("report", "/tmp/report.pdf")), "report")
        XCTAssertEqual(appearance.title(for: fileItem("Makefile", "/tmp/Makefile")), "Makefile")
        XCTAssertEqual(appearance.title(for: fileItem("archive.tar", "/tmp/archive.tar.gz")), "archive.tar")
    }

    func testDotfilesKeepTheirLeadingDot() {
        // ".gitignore" has no extension — the leading dot isn't a suffix separator.
        for mode in [DrawerAppearance.FileExtensions.system, .show, .hide] {
            let appearance = DrawerAppearance(fileExtensions: mode)
            XCTAssertEqual(appearance.title(for: fileItem(".gitignore", "/tmp/.gitignore")), ".gitignore")
        }
        // A dotted hidden file hides only its real suffix.
        let hide = DrawerAppearance(fileExtensions: .hide)
        XCTAssertEqual(hide.title(for: fileItem(".env.local", "/tmp/.env.local")), ".env")
        let show = DrawerAppearance(fileExtensions: .show)
        XCTAssertEqual(show.title(for: fileItem(".env", "/tmp/.env.local")), ".env.local")
    }

    func testCustomLabelsAreShownAsStored() {
        for mode in [DrawerAppearance.FileExtensions.system, .show, .hide] {
            let appearance = DrawerAppearance(fileExtensions: mode)
            XCTAssertEqual(appearance.title(for: fileItem("Quarterly numbers", "/tmp/report.pdf")),
                           "Quarterly numbers")
            // Similar but not exactly the real name → treated as a custom label.
            XCTAssertEqual(appearance.title(for: fileItem("Report.pdf", "/tmp/report.pdf")),
                           "Report.pdf")
            XCTAssertEqual(appearance.title(for: fileItem("report.pd", "/tmp/report.pdf")),
                           "report.pd")
        }
    }

    func testNonFileKindsAreShownAsStored() {
        // Even when a non-file's displayName happens to match its URL's base
        // name ("Safari" is "Safari.app"'s base), only .file items are adjusted.
        let appearance = DrawerAppearance(fileExtensions: .hide)
        XCTAssertEqual(appearance.title(for: DrawerItem(kind: .application, displayName: "Safari",
                                                       url: URL(fileURLWithPath: "/Applications/Safari.app"))),
                       "Safari")
        XCTAssertEqual(appearance.title(for: DrawerItem(kind: .folder, displayName: "Documents",
                                                       url: URL(fileURLWithPath: "/tmp/Documents", isDirectory: true))),
                       "Documents")
        XCTAssertEqual(appearance.title(for: DrawerItem(kind: .url, displayName: "example.com",
                                                       url: URL(string: "https://example.com"))),
                       "example.com")
        XCTAssertEqual(appearance.title(for: DrawerItem(kind: .group, displayName: "Stuff",
                                                       children: [fileItem("report.pdf", "/tmp/report.pdf")])),
                       "Stuff")
        XCTAssertEqual(appearance.title(for: DrawerItem(kind: .trash, displayName: "Trash")),
                       "Trash")
    }

    func testFileItemWithoutURLKeepsStoredName() {
        // A bookmark-only file item has no URL to read the real name from.
        let appearance = DrawerAppearance(fileExtensions: .hide)
        XCTAssertEqual(appearance.title(for: DrawerItem(kind: .file, displayName: "report.pdf")),
                       "report.pdf")
    }
}
