import XCTest
@testable import Top Drawer

final class LauncherDocumentCodableTests: XCTestCase {

    func testFullRoundTrip() throws {
        let item = DrawerItem(kind: .url, displayName: "Example", url: URL(string: "https://example.com"), slot: 4)
        let tab = Tab(
            title: "Work",
            colorHex: "#FF8800",
            glyph: .monogram("W"),
            anchor: ScreenAnchor(displayUUID: "UUID-1", edge: .left, position: 0.25, order: 2),
            items: [item],
            behavior: TabBehavior(openOnHover: true, autoHide: false, keepOpenAfterLaunch: true),
            hotkey: HotkeySpec(keyCode: 13, carbonModifiers: 256)
        )
        let document = LauncherDocument(tabs: [tab])

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: data)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.tabs.first?.glyph, .monogram("W"))
        XCTAssertEqual(decoded.tabs.first?.hotkey, HotkeySpec(keyCode: 13, carbonModifiers: 256))
        XCTAssertEqual(decoded.tabs.first?.items.first?.slot, 4)
    }

    func testSymbolGlyphRoundTrip() throws {
        let glyph = TabGlyph.symbol("folder.fill")
        let data = try JSONEncoder().encode(glyph)
        XCTAssertEqual(try JSONDecoder().decode(TabGlyph.self, from: data), glyph)
    }

    func testTabDecodesWithDefaultsWhenFieldsMissing() throws {
        // Only `anchor` is required; everything else should default.
        let json = #"""
        {"tabs":[{"anchor":{"displayUUID":"D","edge":"right","position":0.5}}]}
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: json)
        let tab = try XCTUnwrap(decoded.tabs.first)
        XCTAssertEqual(tab.title, "Tab")
        XCTAssertEqual(tab.glyph, .default)
        XCTAssertTrue(tab.items.isEmpty)
        XCTAssertEqual(tab.behavior, .default)
        XCTAssertNil(tab.hotkey)
        XCTAssertEqual(tab.gridColumns, 4)
        XCTAssertEqual(tab.gridRows, 2)
        XCTAssertFalse(tab.locked)
        XCTAssertEqual(tab.kind, .items)
        XCTAssertEqual(tab.layout, .grid)
        XCTAssertEqual(tab.notes, "")
        XCTAssertNil(tab.folderURL)
        XCTAssertEqual(tab.recentsSource, .macDring)
        XCTAssertEqual(decoded.version, LauncherDocument.currentVersion)
    }

    func testGridDimensionBoundsMatchForInitializationMutationAndDecoding() throws {
        let cases = [
            (columns: -2, rows: -3, expectedColumns: 1, expectedRows: 1),
            (columns: 1, rows: 1, expectedColumns: 1, expectedRows: 1),
            (columns: 12, rows: 16, expectedColumns: 12, expectedRows: 16),
            (columns: Int.max, rows: Int.max, expectedColumns: 12, expectedRows: 16),
        ]

        for value in cases {
            let tab = Tab(title: "Bounds", colorHex: "#0A84FF",
                          anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5),
                          gridColumns: value.columns, gridRows: value.rows)
            XCTAssertEqual(tab.gridColumns, value.expectedColumns)
            XCTAssertEqual(tab.gridRows, value.expectedRows)

            var mutated = Tab(title: "Mutation", colorHex: "#0A84FF",
                              anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5))
            mutated.gridColumns = value.columns
            mutated.gridRows = value.rows
            XCTAssertEqual(mutated.gridColumns, value.expectedColumns)
            XCTAssertEqual(mutated.gridRows, value.expectedRows)

            let json = #"{"anchor":{"displayUUID":"D","edge":"right","position":0.5},"gridColumns":\#(value.columns),"gridRows":\#(value.rows)}"#.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(Tab.self, from: json)
            XCTAssertEqual(decoded.gridColumns, value.expectedColumns)
            XCTAssertEqual(decoded.gridRows, value.expectedRows)
        }
    }

    func testLayoutRoundTripsAndMigratesLegacyValues() throws {
        let tab = Tab(title: "Fresh", colorHex: "#FF9F0A",
                      anchor: ScreenAnchor(displayUUID: "U", edge: .right, position: 0.5),
                      kind: .fresh, layout: .list)
        let data = try JSONEncoder().encode(LauncherDocument(tabs: [tab]))
        XCTAssertEqual(try JSONDecoder().decode(LauncherDocument.self, from: data).tabs.first?.layout, .list)

        // A tab with no layout, or the old per-tab "useGlobal", migrates to .grid.
        for raw in ["", #","layout":"useGlobal""#] {
            let json = #"{"tabs":[{"anchor":{"displayUUID":"D","edge":"right","position":0.5},"kind":"fresh"\#(raw)}]}"#.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(LauncherDocument.self, from: json)
            XCTAssertEqual(decoded.tabs.first?.layout, .grid, "raw=\(raw)")
        }
    }

    func testDrawerItemDateRoundTrips() throws {
        // A dated transient item (e.g. Fresh) round-trips its date…
        let dated = DrawerItem(kind: .file, displayName: "report.pdf",
                               url: URL(fileURLWithPath: "/x/report.pdf"), slot: 0,
                               date: Date(timeIntervalSince1970: 1_700_000_000))
        let decodedDated = try JSONDecoder().decode(DrawerItem.self, from: JSONEncoder().encode(dated))
        XCTAssertEqual(decodedDated.date, dated.date)

        // …and a normal persisted item (no date) decodes back with a nil date.
        let plain = DrawerItem(kind: .url, displayName: "Example", url: URL(string: "https://example.com"), slot: 1)
        let decodedPlain = try JSONDecoder().decode(DrawerItem.self, from: JSONEncoder().encode(plain))
        XCTAssertNil(decodedPlain.date)
    }

    func testConcealmentRoundTripsAndDefaultsToNever() throws {
        let tab = Tab(title: "Hidden", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "U", edge: .right, position: 0.5),
                      behavior: TabBehavior(concealment: .hide))
        let data = try JSONEncoder().encode(LauncherDocument(tabs: [tab]))
        XCTAssertEqual(try JSONDecoder().decode(LauncherDocument.self, from: data).tabs.first?.behavior.concealment, .hide)

        // A behavior persisted before this field existed decodes as `.never`.
        let legacy = #"""
        {"tabs":[{"anchor":{"displayUUID":"D","edge":"right","position":0.5},
          "behavior":{"openOnHover":true,"autoHide":false,"keepOpenAfterLaunch":false}}]}
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: legacy)
        XCTAssertEqual(decoded.tabs.first?.behavior.concealment, .never)
    }

    func testNotesAndFolderTabsRoundTrip() throws {
        let notes = Tab(title: "Scratch", colorHex: "#FFD60A",
                        anchor: ScreenAnchor(displayUUID: "U", edge: .left, position: 0.4),
                        kind: .notes, notes: "remember the milk")
        let folder = Tab(title: "Downloads", colorHex: "#30D158",
                         anchor: ScreenAnchor(displayUUID: "U", edge: .right, position: 0.6),
                         kind: .folder, folderURL: URL(fileURLWithPath: "/tmp/x"))
        let document = LauncherDocument(tabs: [notes, folder])

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: data)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.tabs[0].kind, .notes)
        XCTAssertEqual(decoded.tabs[0].notes, "remember the milk")
        XCTAssertEqual(decoded.tabs[1].kind, .folder)
        XCTAssertEqual(decoded.tabs[1].folderURL?.path, "/tmp/x")
    }

    func testDisksTabRoundTrips() throws {
        // A Disks tab persists only its kind — its volume items are listed live and
        // are never stored in the document.
        let disks = Tab(title: "Disks", colorHex: "#BF5AF2",
                        anchor: ScreenAnchor(displayUUID: "U", edge: .right, position: 0.7),
                        kind: .disks)
        let data = try JSONEncoder().encode(LauncherDocument(tabs: [disks]))
        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: data)
        XCTAssertEqual(decoded.tabs.first?.kind, .disks)
        XCTAssertTrue(decoded.tabs.first?.items.isEmpty ?? false)
    }

    func testRecentsSourceRoundTripsAndDefaultsToMacDring() throws {
        let tab = Tab(title: "Recents", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "U", edge: .right, position: 0.5),
                      kind: .recents, recentsSource: .both)
        let data = try JSONEncoder().encode(LauncherDocument(tabs: [tab]))
        XCTAssertEqual(try JSONDecoder().decode(LauncherDocument.self, from: data).tabs.first?.recentsSource, .both)

        // A recents tab persisted before the source field existed decodes as `.macDring`.
        let legacy = #"""
        {"tabs":[{"anchor":{"displayUUID":"D","edge":"right","position":0.5},"kind":"recents"}]}
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: legacy)
        XCTAssertEqual(decoded.tabs.first?.recentsSource, .macDring)
    }

    func testFreshTabRoundTrips() throws {
        // A Fresh tab persists only its kind — its items are listed live (Spotlight)
        // and are never stored in the document.
        let fresh = Tab(title: "Fresh", colorHex: "#FF9F0A",
                        anchor: ScreenAnchor(displayUUID: "U", edge: .right, position: 0.5),
                        kind: .fresh)
        let data = try JSONEncoder().encode(LauncherDocument(tabs: [fresh]))
        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: data)
        XCTAssertEqual(decoded.tabs.first?.kind, .fresh)
        XCTAssertTrue(decoded.tabs.first?.items.isEmpty ?? false)
    }

    func testDateRankedTabKindsDefaultToListLayout() {
        XCTAssertEqual(TabKind.recents.defaultLayout, .list)
        XCTAssertEqual(TabKind.fresh.defaultLayout, .list)
        XCTAssertEqual(TabKind.items.defaultLayout, .grid)
        XCTAssertEqual(TabKind.folder.defaultLayout, .grid)
    }

    func testOneMalformedTabIsDroppedNotTheWholeDocument() throws {
        // The first tab is missing its required `anchor`; the second is valid.
        // The bad record should be skipped while the good one survives — losing a
        // single tab must never wipe the whole arranged launcher.
        let json = #"""
        {"tabs":[
          {"title":"Broken"},
          {"title":"Good","anchor":{"displayUUID":"D","edge":"right","position":0.5}}
        ]}
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: json)
        XCTAssertEqual(decoded.tabs.count, 1)
        XCTAssertEqual(decoded.tabs.first?.title, "Good")
    }

    func testEmptyDocumentDecodes() throws {
        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: "{}".data(using: .utf8)!)
        XCTAssertTrue(decoded.tabs.isEmpty)
        XCTAssertEqual(decoded.version, LauncherDocument.currentVersion)
    }
}
