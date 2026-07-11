import XCTest
@testable import MacDring

final class ItemLauncherTests: XCTestCase {

    private enum TestError: Error { case failed }

    func testSynchronousOpenFailureCompletesOnMainWithTarget() {
        let url = URL(fileURLWithPath: "/tmp/missing.txt")
        let item = DrawerItem(kind: .file, displayName: "Missing", url: url)
        let completed = expectation(description: "launch completed")
        var completionCount = 0

        DispatchQueue.global().async {
            ItemLauncher.launch(
                item,
                resolveURL: { $0.url },
                openApplication: { _, _ in XCTFail("File launch must not use the application opener") },
                openURL: { _ in false }
            ) { result in
                completionCount += 1
                XCTAssertTrue(Thread.isMainThread)
                guard case let .failure(.workspaceOpenFailed(failedURL)) = result else {
                    XCTFail("Expected workspace-open failure, got \(result)")
                    completed.fulfill()
                    return
                }
                XCTAssertEqual(failedURL, url)
                completed.fulfill()
            }
        }

        waitForExpectations(timeout: 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testApplicationErrorCompletesExactlyOnceOnMain() {
        let url = URL(fileURLWithPath: "/Applications/Missing.app")
        let item = DrawerItem(kind: .application, displayName: "Missing", url: url)
        let completed = expectation(description: "launch completed")
        var completionCount = 0

        ItemLauncher.launch(
            item,
            resolveURL: { $0.url },
            openApplication: { _, reply in
                DispatchQueue.global().async {
                    reply(TestError.failed)
                    reply(nil)   // A misbehaving dependency must not complete twice.
                }
            },
            openURL: { _ in
                XCTFail("Application launch must not use the synchronous URL opener")
                return true
            }
        ) { result in
            completionCount += 1
            XCTAssertTrue(Thread.isMainThread)
            guard case let .failure(.applicationOpenFailed(failedURL, error)) = result else {
                XCTFail("Expected application-open failure, got \(result)")
                completed.fulfill()
                return
            }
            XCTAssertEqual(failedURL, url)
            XCTAssertTrue(error is TestError)
            completed.fulfill()
        }

        waitForExpectations(timeout: 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testSuccessfulOpenReturnsResolvedURL() {
        let storedURL = URL(fileURLWithPath: "/old/location.txt")
        let resolvedURL = URL(fileURLWithPath: "/new/location.txt")
        let item = DrawerItem(kind: .file, displayName: "Moved", url: storedURL)
        var openedURL: URL?
        var result: ItemLauncher.LaunchResult?

        ItemLauncher.launch(
            item,
            resolveURL: { _ in resolvedURL },
            openApplication: { _, _ in XCTFail("File launch must not use the application opener") },
            openURL: {
                openedURL = $0
                return true
            },
            completion: { result = $0 }
        )

        XCTAssertEqual(openedURL, resolvedURL)
        guard case let .success(confirmedURL)? = result else {
            XCTFail("Expected successful launch, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(confirmedURL, resolvedURL)
    }

    func testUnresolvedTargetDoesNotAttemptWorkspaceOpen() {
        let item = DrawerItem(kind: .file, displayName: "Broken")
        var attemptedOpen = false
        var result: ItemLauncher.LaunchResult?

        ItemLauncher.launch(
            item,
            resolveURL: { _ in nil },
            openApplication: { _, _ in attemptedOpen = true },
            openURL: { _ in
                attemptedOpen = true
                return true
            },
            completion: { result = $0 }
        )

        XCTAssertFalse(attemptedOpen)
        guard case .failure(.unresolvedTarget)? = result else {
            XCTFail("Expected unresolved-target failure, got \(String(describing: result))")
            return
        }
    }
}
