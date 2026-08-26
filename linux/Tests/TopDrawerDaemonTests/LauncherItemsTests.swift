import XCTest
@testable import TopDrawerDaemon

#if os(Linux)
/// Item-by-ID resolution out of the raw launcher JSON (the `Launch(itemID)` lookup).
final class LauncherItemsTests: XCTestCase {

    private let doc = #"""
    {"version":1,"tabs":[
      {"id":"t1","kind":"items","items":[
        {"id":"a","kind":"file","displayName":"Report","url":"file:///home/alice/report.pdf"},
        {"id":"g","kind":"group","displayName":"Group","children":[
          {"id":"b","kind":"application","displayName":"Editor","url":"file:///usr/share/applications/gedit.desktop"}
        ]}
      ]},
      {"id":"t2","kind":"items","items":[
        {"id":"c","kind":"url","displayName":"Site","url":"https://example.com"}
      ]}
    ]}
    """#

    func testFindsTopLevelItem() {
        let item = LauncherItems.find(id: "a", in: doc)
        XCTAssertEqual(item?.kind, "file")
        XCTAssertEqual(item?.name, "Report")
        XCTAssertEqual(item?.url, "file:///home/alice/report.pdf")
        XCTAssertEqual(item?.targetURL?.path, "/home/alice/report.pdf")
    }

    func testDescendsIntoGroupChildren() {
        let item = LauncherItems.find(id: "b", in: doc)
        XCTAssertEqual(item?.kind, "application")
        XCTAssertEqual(item?.url, "file:///usr/share/applications/gedit.desktop")
    }

    func testFindsItemInASecondTab() {
        XCTAssertEqual(LauncherItems.find(id: "c", in: doc)?.targetURL?.absoluteString,
                       "https://example.com")
    }

    func testUnknownIDIsNil() {
        XCTAssertNil(LauncherItems.find(id: "zzz", in: doc))
    }

    func testMalformedJSONIsNil() {
        XCTAssertNil(LauncherItems.find(id: "a", in: "not json"))
        XCTAssertNil(LauncherItems.find(id: "a", in: "{}"))
    }
}
#endif
