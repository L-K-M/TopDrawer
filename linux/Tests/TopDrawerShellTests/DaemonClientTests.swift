#if os(Linux)
import DBUS
import MacDring
import TopDrawerDaemon
import XCTest

@testable import TopDrawerShell

/// The LP-20 acceptance: the shell's D-Bus client, exercised against a live mock
/// daemon — a real `TopDrawerService` whose backends are all injected fakes/fixtures
/// — over a private session bus (`dbus-run-session -- swift test --package-path
/// linux`; plain `swift test` skips these, exactly like the daemon's own tests).
final class DaemonClientTests: XCTestCase {

    /// These tests claim the daemon's well-known name on the bus they're given, so
    /// they must only run on a throwaway `dbus-run-session` bus — never a desktop's
    /// live session bus, where `DBUS_SESSION_BUS_ADDRESS` is always set and the mock
    /// would shadow (or fight) a real topdrawerd. The sentinel is the opt-in marker
    /// `dbus-run-session` can't provide by itself.
    static let privateTestBusFlag = "TOPDRAWER_PRIVATE_TEST_BUS"

    private var tempDir: URL!
    private var launcherURL: URL!
    private var serverTask: Task<Void, Never>?

    override func setUpWithError() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment[Self.privateTestBusFlag] == nil,
            "not a private test bus — run under `dbus-run-session -- env \(Self.privateTestBusFlag)=1 swift test --package-path linux`")
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("topdrawer-shell-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        launcherURL = tempDir.appendingPathComponent("launcher.json")
        try Self.document(tabs: [("apps", "Apps"), ("files", "Files")])
            .write(to: launcherURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        // Wait for the mock's connection to close so it releases the DO_NOT_QUEUE bus
        // name before the next test's mock claims it (same reasoning as the daemon's
        // own test harness).
        serverTask?.cancel()
        await serverTask?.value
        serverTask = nil
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private static func document(tabs: [(String, String)]) -> String {
        let list = tabs.map { #"{"id":"\#($0.0)","title":"\#($0.1)","kind":"items"}"# }
            .joined(separator: ",")
        return #"{"version":1,"tabs":[\#(list)]}"#
    }

    /// Starts the mock daemon: a real `TopDrawerService` over the launcher fixture,
    /// with every other backend pinned to hermetic no-op fakes (the client tests only
    /// ever drive `GetDocument` / `DocumentChanged`).
    private func startMockDaemon(watchInterval: Duration = .milliseconds(200)) {
        serverTask = Task {
            do {
                try await DBusClient.withSessionBus(auth: .external(userID: String(getuid()))) { connection in
                    let service = TopDrawerService(
                        source: LauncherDocumentSource(url: self.launcherURL),
                        trashService: FakeTrashService(),
                        trashDirectory: self.tempDir.appendingPathComponent("trash", isDirectory: true),
                        recentsProvider: FakeRecentsProvider(),
                        launcher: FakeLauncher(),
                        recorder: FakeRecorder(),
                        runningApps: FakeRunningApps(),
                        xbelLocation: self.tempDir.appendingPathComponent("recently-used.xbel"),
                        freshScopes: [self.tempDir.appendingPathComponent("fresh", isDirectory: true)])
                    try await service.run(on: connection, watchInterval: watchInterval)
                    try await Task.sleep(for: .seconds(30))
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    XCTFail("mock daemon failed: \(error)")
                }
            }
        }
    }

    private func withClient(_ body: @escaping @Sendable (DBusClient.Connection) async throws -> Void) async throws {
        try await DBusClient.withSessionBus(auth: .external(userID: String(getuid()))) { client in
            try await body(client)
        }
    }

    // MARK: - One-shot fetch

    func testFetchTabsReadsTheDaemonDocument() async throws {
        startMockDaemon()
        try await withClient { client in
            // The mock races the client at startup; Ping until it owns the name.
            let tabs = try await Self.untilTabs(client)
            XCTAssertEqual(tabs.map(\.title), ["Apps", "Files"])
        }
    }

    func testFetchTabsFailsCleanlyWithoutADaemon() async throws {
        try await withClient { client in
            do {
                _ = try await DaemonClient.fetchTabs(client)
                XCTFail("expected a failure — nothing owns the name")
            } catch {
                // ServiceUnknown surfaces as an error reply; anything but a tab list is fine.
            }
        }
    }

    // MARK: - Change observation

    func testObserveTabsEmitsTheStripThenTheChangedStrip() async throws {
        startMockDaemon()
        try await withClient { client in
            // Observe only once the mock owns the name, so the strict onError below
            // pins real failures, not the startup race (the app-level observeTabs
            // retries through that race by design).
            try await Self.pingReady(client)
            let strips = TabStripRecorder()
            let observation = Task {
                await DaemonClient.observeTabs(client,
                                               onChange: { strips.record($0) },
                                               onError: {
                                                   // Teardown races the observer: once
                                                   // cancelled, connection errors are
                                                   // expected shutdown interleaving.
                                                   guard !Task.isCancelled else { return }
                                                   XCTFail("unexpected error: \($0)")
                                               },
                                               retryDelay: .milliseconds(100))
            }

            // Initial strip arrives once the mock owns the name…
            try await Self.waitUntil { strips.all.first == ["Apps", "Files"] }

            // …and rewriting the launcher document drives DocumentChanged → a new strip.
            try Self.document(tabs: [("apps", "Apps"), ("trash", "Trash")])
                .write(to: self.launcherURL, atomically: true, encoding: .utf8)
            try await Self.waitUntil { strips.all.last == ["Apps", "Trash"] }

            observation.cancel()
        }
    }

    // MARK: - Helpers

    private static func untilTabs(_ client: DBusClient.Connection,
                                  attempts: Int = 40) async throws -> [ShellTab] {
        for _ in 0..<attempts {
            if let tabs = try? await DaemonClient.fetchTabs(client), !tabs.isEmpty { return tabs }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTFail("mock daemon never became ready")
        return []
    }

    /// Pings until the mock's method returns — it races the client at startup (the
    /// name is claimed late on purpose since PR #123).
    private static func pingReady(_ client: DBusClient.Connection,
                                  attempts: Int = 40) async throws {
        for _ in 0..<attempts {
            if let reply = try? await client.send(
                .createMethodCall(
                    destination: DaemonClient.busName, path: DaemonClient.objectPath,
                    interface: DaemonClient.interfaceName, method: "Ping", body: []),
                timeoutNanoseconds: 5_000_000_000),
               reply.messageType == .methodReturn { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTFail("mock daemon never answered Ping")
    }

    /// Polls `condition` on a short cadence until it holds or `timeout` elapses — a
    /// signal-driven event is asynchronous, so a fixed sleep would flake under load.
    private static func waitUntil(_ condition: @escaping () -> Bool,
                                  timeout: Duration = .seconds(10),
                                  what: String = "condition") async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("timed out waiting for \(what)")
    }
}

/// The observed tab strips, lock-guarded: `observeTabs` delivers from the D-Bus
/// reader task while the test asserts from its own task.
final class TabStripRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var strips: [[ShellTab]] = []

    func record(_ tabs: [ShellTab]) {
        lock.lock(); strips.append(tabs); lock.unlock()
    }

    /// Every recorded strip's titles, oldest first.
    var all: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return strips.map { $0.map(\.title) }
    }
}

// MARK: - Hermetic no-op backends (same shape as the daemon tests' fakes)

private struct FakeTrashService: TrashServicing {
    func trashCount() -> Int { 0 }
    func trashIsEmpty() -> Bool { true }
    func trash(_ urls: [URL]) -> Bool { true }
    func emptyTrash() -> Bool { true }
}

private struct FakeRecentsProvider: RecentsProviding {
    func systemRecents(limit: Int) -> [RecentFileHit] { [] }
    func fresh(limit: Int) -> [RecentFileHit] { [] }
}

private struct FakeLauncher: LinuxLaunching {
    func launch(_ item: LauncherItem) -> Bool { true }
    func openWith(desktopID: String, uris: [String]) -> Bool { true }
    func reveal(uri: String) -> Bool { true }
}

private struct FakeRecorder: RecentsRecording {
    func record(url: URL, kind: String, name: String, date: Date) async {}
    func recents(limit: Int) async -> [RecentFileHit] { [] }
}

private struct FakeRunningApps: RunningAppsScanning {
    func runningAppIDs() -> [String]? { [] }
}
#endif
