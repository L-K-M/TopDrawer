import XCTest
@testable import MacDring

final class FreshScannerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreshScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func touch(_ name: String, in dir: URL? = nil) throws -> URL {
        let url = (dir ?? root).appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    func testNewestAddedFirstWithInjectedDates() throws {
        try touch("new.txt")
        try touch("old.txt")
        try touch("mid.txt")
        let ages: [String: Double] = ["new.txt": 1, "mid.txt": 5, "old.txt": 20]   // days ago
        let now = Date()

        let results = FreshScanner.results(scopes: [root], limit: 40, now: now) { url in
            now.addingTimeInterval(-(ages[url.lastPathComponent] ?? 0) * 86400)
        }
        XCTAssertEqual(results.map(\.url.lastPathComponent), ["new.txt", "mid.txt", "old.txt"])
    }

    func testFilesOlderThanTheWindowAreExcluded() throws {
        try touch("fresh.txt")
        try touch("stale.txt")
        let now = Date()
        let beyond = FreshScanner.window + 86400   // a day past the cutoff

        let results = FreshScanner.results(scopes: [root], limit: 40, now: now) { url in
            url.lastPathComponent == "stale.txt" ? now.addingTimeInterval(-beyond) : now
        }
        XCTAssertEqual(results.map(\.url.lastPathComponent), ["fresh.txt"])
    }

    func testHiddenFilesAreSkipped() throws {
        try touch("visible.txt")
        try touch(".hidden")
        let results = FreshScanner.results(scopes: [root], limit: 40) { _ in Date() }
        XCTAssertEqual(results.map(\.url.lastPathComponent), ["visible.txt"])
    }

    func testCapsToLimit() throws {
        for i in 0..<10 { try touch("f\(i).txt") }
        let results = FreshScanner.results(scopes: [root], limit: 3) { _ in Date() }
        XCTAssertEqual(results.count, 3)
    }

    func testDeduplicatesAcrossScopesByURL() throws {
        // The same directory passed twice must not double-count its files.
        try touch("once.txt")
        let results = FreshScanner.results(scopes: [root, root], limit: 40) { _ in Date() }
        XCTAssertEqual(results.filter { $0.url.lastPathComponent == "once.txt" }.count, 1)
    }

    func testMissingScopeContributesNothing() throws {
        try touch("real.txt")
        let ghost = root.appendingPathComponent("does-not-exist", isDirectory: true)
        let results = FreshScanner.results(scopes: [ghost, root], limit: 40) { _ in Date() }
        XCTAssertEqual(results.map(\.url.lastPathComponent), ["real.txt"])
    }

    func testRealDateAddedSurfacesJustCreatedFiles() throws {
        // Exercises the real Date-Added read path (no injection): a freshly written
        // file is, by definition, within the window — so it must show up. This is the
        // crux of working *without* Spotlight.
        try touch("just-arrived.txt")
        let results = FreshScanner.results(scopes: [root], limit: 40)
        XCTAssertTrue(results.contains { $0.url.lastPathComponent == "just-arrived.txt" })
    }
}
