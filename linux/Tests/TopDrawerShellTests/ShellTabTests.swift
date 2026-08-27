#if os(Linux)
import XCTest

@testable import TopDrawerShell

final class ShellTabTests: XCTestCase {

    func testParseKeepsDocumentOrderAndReadsTitleKindAndFallbacks() {
        let json = #"""
        {"version":1,"tabs":[
          {"id":"apps","title":"Apps","kind":"items"},
          {"id":"recent","kind":"recents"},
          {"id":"fresh","title":"Fresh"}
        ]}
        """#

        XCTAssertEqual(ShellTab.parse(json), [
            ShellTab(id: "apps", title: "Apps", kind: "items"),
            ShellTab(id: "recent", title: "recent", kind: "recents"),   // no title → the id labels the pill
            ShellTab(id: "fresh", title: "Fresh", kind: "items"),        // no kind → the items default
        ])
    }

    func testParseSkipsTabsWithoutAnID() {
        let json = #"{"version":1,"tabs":[{"title":"Ghost"},{"id":"real","title":"Real"}]}"#
        XCTAssertEqual(ShellTab.parse(json).map(\.id), ["real"])
    }

    func testParseOfGarbageOrEmptyDocumentsYieldsNoTabs() {
        XCTAssertEqual(ShellTab.parse(""), [])
        XCTAssertEqual(ShellTab.parse("not json"), [])
        XCTAssertEqual(ShellTab.parse(#"{"version":1,"tabs":[]}"#), [])
        XCTAssertEqual(ShellTab.parse(#"{"version":1}"#), [])   // no tabs array at all
    }
}
#endif
