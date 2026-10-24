import XCTest
#if canImport(AppKit)
import AppKit   // NSImage — the `applications(toOpen:)` signature needs it
#endif
@testable import MacDring

/// Tests for the seam-injected `open` core and `isValidApplication` — all pure
/// Foundation, so they run wherever `ItemActionService`'s core compiles. The
/// `NSWorkspace`-backed halves are exercised manually in a GUI session; only the
/// dedup/sort/filter logic has an AppKit-only test (`Application` needs `NSImage`).
final class ItemActionServiceTests: XCTestCase {

    private enum TestError: Error { case failed }

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ItemActionServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    /// A real on-disk `.app` directory, so the real `isValidApplication` accepts it.
    private func makeFakeApp(named name: String = "Fake") throws -> URL {
        let url = tempDir.appendingPathComponent("\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The failure end of a `Result<URL, Error>` as an `ActionError`, or nil.
    private func actionError(_ result: Result<URL, Error>?) -> ItemActionService.ActionError? {
        guard case .failure(let error)? = result else { return nil }
        return error as? ItemActionService.ActionError
    }

    // MARK: isValidApplication

    func testIsValidApplication() throws {
        let app = try makeFakeApp()
        XCTAssertTrue(ItemActionService.isValidApplication(app))
        XCTAssertFalse(ItemActionService.isValidApplication(
            tempDir.appendingPathComponent("Missing.app", isDirectory: true)))
        XCTAssertFalse(ItemActionService.isValidApplication(tempDir))   // a dir, not .app
        XCTAssertFalse(ItemActionService.isValidApplication(
            URL(string: "https://example.com/Fake.app")!))              // not local
        let plain = tempDir.appendingPathComponent("plain.txt")
        _ = FileManager.default.createFile(atPath: plain.path, contents: Data())
        XCTAssertFalse(ItemActionService.isValidApplication(plain))     // a file, not a bundle
    }

    // MARK: open — seam core

    func testOpenWithInvalidApplicationFailsWithoutOpening() {
        let badApp = URL(fileURLWithPath: "/tmp/NotAnApp.txt")
        let item = DrawerItem(kind: .file, displayName: "Doc",
                              url: URL(fileURLWithPath: "/tmp/doc.txt"))
        var openAttempted = false
        var result: Result<URL, Error>?

        ItemActionService.open(
            item, withApplicationAt: badApp,
            resolveURL: { $0.url },
            isValidApplication: ItemActionService.isValidApplication,
            openURLs: { _, _, _ in openAttempted = true },
            completion: { result = $0 })

        XCTAssertFalse(openAttempted)
        XCTAssertEqual(actionError(result), .invalidApplication(badApp))
    }

    func testOpenUnresolvedTargetFailsWithoutOpening() throws {
        let app = try makeFakeApp()
        let item = DrawerItem(kind: .file, displayName: "Gone")
        var openAttempted = false
        var result: Result<URL, Error>?

        ItemActionService.open(
            item, withApplicationAt: app,
            resolveURL: { _ in nil },
            isValidApplication: ItemActionService.isValidApplication,
            openURLs: { _, _, _ in openAttempted = true },
            completion: { result = $0 })

        XCTAssertFalse(openAttempted)
        XCTAssertEqual(actionError(result), .unresolvedTarget)
    }

    func testOpenDeliversResolvedTargetAndReportsSuccess() throws {
        let app = try makeFakeApp()
        let resolved = URL(fileURLWithPath: "/new/location.txt")
        let item = DrawerItem(kind: .file, displayName: "Moved",
                              url: URL(fileURLWithPath: "/old/location.txt"))
        var opened: (urls: [URL], app: URL)?
        var result: Result<URL, Error>?

        ItemActionService.open(
            item, withApplicationAt: app,
            resolveURL: { _ in resolved },
            isValidApplication: ItemActionService.isValidApplication,
            openURLs: { urls, app, reply in
                opened = (urls, app)
                reply(nil)
            },
            completion: { result = $0 })

        XCTAssertEqual(opened?.urls, [resolved])
        XCTAssertEqual(opened?.app, app)
        guard case .success(let confirmed)? = result else {
            XCTFail("Expected success, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(confirmed, resolved)
    }

    func testOpenErrorCompletesExactlyOnceOnMain() throws {
        let app = try makeFakeApp()
        let target = URL(fileURLWithPath: "/tmp/doc.txt")
        let item = DrawerItem(kind: .file, displayName: "Doc", url: target)
        let completed = expectation(description: "open completed")
        var completionCount = 0

        DispatchQueue.global().async {
            ItemActionService.open(
                item, withApplicationAt: app,
                resolveURL: { $0.url },
                isValidApplication: ItemActionService.isValidApplication,
                openURLs: { _, _, reply in
                    DispatchQueue.global().async {
                        reply(TestError.failed)
                        reply(nil)   // a misbehaving backend must not complete twice
                    }
                },
                completion: { result in
                    completionCount += 1
                    XCTAssertTrue(Thread.isMainThread)
                    guard case .failure(let error) = result,
                          let actionError = error as? ItemActionService.ActionError,
                          case .openFailed(let failedTarget, let underlying) = actionError else {
                        XCTFail("Expected openFailed, got \(String(describing: result))")
                        completed.fulfill()
                        return
                    }
                    XCTAssertEqual(failedTarget, target)
                    XCTAssertTrue(underlying is TestError)
                    completed.fulfill()
                })
        }

        waitForExpectations(timeout: 1)
        XCTAssertEqual(completionCount, 1)
    }

    // MARK: application enumeration (AppKit — `Application` carries NSImage)

    #if canImport(AppKit)
    func testApplicationsDedupSortsAndFilters() throws {
        let alpha = try makeFakeApp(named: "alpha")
        let beta = try makeFakeApp(named: "Beta")
        let missing = tempDir.appendingPathComponent("Ghost.app", isDirectory: true)
        let notApp = tempDir.appendingPathComponent("notapp.txt")
        _ = FileManager.default.createFile(atPath: notApp.path, contents: Data())
        // The same bundle reached two ways — a trailing-slash variant — dedups.
        let alphaAlias = URL(fileURLWithPath: alpha.path + "/", isDirectory: true)
        let target = URL(fileURLWithPath: "/tmp/doc.txt")

        let apps = ItemActionService.applications(
            toOpen: target,
            applicationURLs: { _ in [beta, alphaAlias, missing, notApp, alpha] },
            icon: { _ in NSImage() })

        XCTAssertEqual(apps.map(\.url.standardizedFileURL),
                       [alpha.standardizedFileURL, beta.standardizedFileURL])
        XCTAssertEqual(apps.map(\.name), ["alpha", "Beta"])
        XCTAssertEqual(apps.map(\.id), apps.map(\.url.standardizedFileURL))
    }

    func testApplicationsForItemWithoutTargetIsEmpty() {
        let group = DrawerItem(kind: .group, displayName: "Group")
        XCTAssertTrue(ItemActionService.applications(for: group).isEmpty)
    }
    #endif
}
