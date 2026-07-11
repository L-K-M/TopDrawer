import XCTest
@testable import MacDring

final class TimeBucketTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)
    private lazy var now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!

    private func day(_ d: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: d, hour: hour))!
    }

    func testBucketBoundaries() {
        XCTAssertEqual(TimeBucket.bucket(for: now, now: now, calendar: cal), .today)
        XCTAssertEqual(TimeBucket.bucket(for: day(15, hour: 1), now: now, calendar: cal), .today)
        XCTAssertEqual(TimeBucket.bucket(for: day(14), now: now, calendar: cal), .yesterday)
        XCTAssertEqual(TimeBucket.bucket(for: day(11), now: now, calendar: cal), .thisWeek)   // 4 days ago
        XCTAssertEqual(TimeBucket.bucket(for: day(8), now: now, calendar: cal), .thisWeek)     // exactly 7 days ago
        XCTAssertEqual(TimeBucket.bucket(for: day(7), now: now, calendar: cal), .older)        // 8 days ago
        XCTAssertEqual(TimeBucket.bucket(for: day(1), now: now, calendar: cal), .older)
    }

    func testGroupedKeepsOrderAndDropsEmptyBuckets() {
        struct Row { let name: String; let date: Date? }
        let rows = [
            Row(name: "a", date: now),
            Row(name: "b", date: day(14)),
            Row(name: "c", date: day(15, hour: 2)),
            Row(name: "d", date: nil),          // nil date → Older
            Row(name: "e", date: day(2)),       // Older
        ]
        let sections = TimeBucket.grouped(rows, now: now, calendar: cal) { $0.date }

        // Today and Yesterday and Older present; This Week absent (dropped).
        XCTAssertEqual(sections.map(\.bucket), [.today, .yesterday, .older])
        XCTAssertEqual(sections[0].items.map(\.name), ["a", "c"])   // order preserved within bucket
        XCTAssertEqual(sections[1].items.map(\.name), ["b"])
        XCTAssertEqual(sections[2].items.map(\.name), ["d", "e"])
    }
}
