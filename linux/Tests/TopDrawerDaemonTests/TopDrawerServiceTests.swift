#if os(Linux)
import XCTest
import Foundation
import Glibc
import DBUS
import MacDring
@testable import TopDrawerDaemon

/// End-to-end tests: a real `TopDrawerService` exported on the session bus, driven
/// by a separate client connection. They need a bus, so run them under
/// `dbus-run-session -- swift test --package-path linux` (plain `swift test` skips
/// them). This is the LP-16 acceptance: `Ping` (and the rest of the interface) over
/// a real D-Bus round trip.
final class TopDrawerServiceTests: XCTestCase {

    private var tempDir: URL!
    private var launcherURL: URL!
    private let launcherJSON = #"{"version":1,"tabs":[{"id":"apps","title":"Apps"}]}"#
    private var serverTask: Task<Void, Never>?

    override func setUpWithError() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["DBUS_SESSION_BUS_ADDRESS"] == nil,
            "no session bus — run under `dbus-run-session -- swift test --package-path linux`")
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("topdrawerd-svc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        launcherURL = tempDir.appendingPathComponent("launcher.json")
        try launcherJSON.write(to: launcherURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        // Await the cancelled task, don't just drop it: the server holds the well-known
        // name `ch.lkmc.TopDrawer` until its `withSessionBus` scope closes, and the name is
        // claimed DO_NOT_QUEUE. If the next test's server raced in before this one's scope
        // released the name, its RequestName would fail and surface as a flaky
        // "service never became ready" timeout. Waiting for `value` blocks until the
        // connection is torn down and the name is free.
        serverTask?.cancel()
        await serverTask?.value
        serverTask = nil
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Tests

    func testPingGetDocumentAndStubsRoundTripOverDBus() async throws {
        startServer()
        try await withClient { client in
            let ping = try await self.callReady(client, method: "Ping")
            XCTAssertEqual(ping.body.first?.string, "topdrawerd \(TopDrawerService.version) alive")

            let doc = try await self.call(client, method: "GetDocument")
            XCTAssertEqual(doc.messageType, .methodReturn, "\(doc)")
            XCTAssertEqual(doc.body.first?.string, self.launcherJSON, "GetDocument serves the file verbatim")

            let launch = try await self.call(client, method: "Launch", body: [.string("some-item")])
            XCTAssertEqual(launch.body.first?.boolean, false, "Launch is a skeleton stub (LP-19)")

            let dropped = try await self.call(
                client, method: "AddDroppedURIs",
                body: [.string("tab"), .array([.string("file:///tmp/x")])])
            XCTAssertEqual(dropped.body.first?.boolean, false, "AddDroppedURIs is a skeleton stub (LP-17)")
        }
    }

    func testIntrospectionExportsTheInterfaceMethodsAndSignal() async throws {
        startServer()
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")   // wait until exported
            let reply = try await client.send(
                .createMethodCall(
                    destination: TopDrawerService.busName,
                    path: TopDrawerService.objectPath,
                    interface: "org.freedesktop.DBus.Introspectable",
                    method: "Introspect"),
                timeoutNanoseconds: 5_000_000_000)
            let xml = try XCTUnwrap(reply?.body.first?.string)
            XCTAssertTrue(xml.contains(#"interface name="ch.lkmc.TopDrawer1""#), xml)
            for method in ["Ping", "GetDocument", "GetVolumes", "Eject", "GetTrashState",
                           "Launch", "AddDroppedURIs"] {
                XCTAssertTrue(xml.contains(#"method name="\#(method)""#), "missing \(method) in \(xml)")
            }
            for signal in ["DocumentChanged", "VolumesChanged", "TrashChanged"] {
                XCTAssertTrue(xml.contains(#"signal name="\#(signal)""#), "missing \(signal) in \(xml)")
            }
        }
    }

    func testDocumentChangedSignalFiresWhenTheLauncherFileChanges() async throws {
        startServer()
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")   // wait until exported
            // Ask the bus to route our signal to this client, then subscribe locally.
            _ = try await client.send(
                .createMethodCall(
                    destination: "org.freedesktop.DBus",
                    path: "/org/freedesktop/DBus",
                    interface: "org.freedesktop.DBus",
                    method: "AddMatch",
                    body: [.string("type='signal',interface='\(TopDrawerService.interfaceName)',member='DocumentChanged'")]),
                timeoutNanoseconds: 5_000_000_000)
            let signals = await client.subscribeToSignal(
                interface: TopDrawerService.interfaceName, member: "DocumentChanged")

            // Change the launcher file — the daemon's modification-time watch should notice
            // and broadcast DocumentChanged.
            try #"{"version":1,"tabs":[]}"#.write(to: self.launcherURL, atomically: true, encoding: .utf8)

            let received = await Self.firstElement(of: signals, timeout: .seconds(10))
            XCTAssertNotNil(received, "DocumentChanged should fire after the launcher file changes")
            XCTAssertEqual(received?.member, "DocumentChanged")
        }
    }

    // MARK: - LP-17: volumes / trash

    func testGetVolumesSerializesTheInjectedSnapshotAsJSON() async throws {
        let volumes = [
            LinuxVolume(id: "/media/alice/USB", name: "USB", path: "/media/alice/USB",
                        kind: .disk, device: "/dev/sdb1", ejectable: true),
            LinuxVolume(id: "/home/alice/nas", name: "nas", path: "/home/alice/nas",
                        kind: .network, device: "//server/share", ejectable: true),
        ]
        startServer(volumeSource: FakeVolumeSource(volumes))
        try await withClient { client in
            let reply = try await self.callReady(client, method: "GetVolumes")
            let json = try XCTUnwrap(reply.body.first?.string)
            let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            let list = try XCTUnwrap(root?["volumes"] as? [[String: Any]])
            XCTAssertEqual(list.count, 2)
            XCTAssertEqual(list.first?["kind"] as? String, "disk")
            XCTAssertEqual(list.first?["name"] as? String, "USB")
            XCTAssertEqual(list.last?["kind"] as? String, "network")
        }
    }

    func testGetTrashStateReportsTheInjectedCountAndEmptiness() async throws {
        startServer(trashService: FakeTrashService(count: 3))
        try await withClient { client in
            let reply = try await self.callReady(client, method: "GetTrashState")
            XCTAssertEqual(reply.body.first?.boolean, false, "3 items → not empty")
            XCTAssertEqual(reply.body.dropFirst().first?.uint32, 3)
        }
    }

    func testEjectResolvesTheVolumeIDAndInvokesTheEjector() async throws {
        let volume = LinuxVolume(id: "/media/alice/USB", name: "USB", path: "/media/alice/USB",
                                 kind: .disk, device: "/dev/sdb1", ejectable: true)
        startServer(volumeSource: FakeVolumeSource([volume]), ejector: { $0.device == "/dev/sdb1" })
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let unknown = try await self.call(client, method: "Eject", body: [.string("/no/such")])
            XCTAssertEqual(unknown.body.first?.boolean, false, "an unknown id ejects nothing")

            let known = try await self.call(client, method: "Eject", body: [.string("/media/alice/USB")])
            XCTAssertEqual(known.body.first?.boolean, true, "a known id is handed to the ejector")
        }
    }

    func testTrashChangedFiresWhenTheTrashDirectoryChanges() async throws {
        let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
        let files = trashDir.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        startServer(trashDirectory: trashDir)
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")   // wait until exported
            _ = try await client.send(
                .createMethodCall(
                    destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                    interface: "org.freedesktop.DBus", method: "AddMatch",
                    body: [.string("type='signal',interface='\(TopDrawerService.interfaceName)',member='TrashChanged'")]),
                timeoutNanoseconds: 5_000_000_000)
            let signals = await client.subscribeToSignal(
                interface: TopDrawerService.interfaceName, member: "TrashChanged")

            // Trash a file — the inotify watch on files/ should notice the new entry.
            try "gone".write(to: files.appendingPathComponent("deleted.txt"),
                             atomically: true, encoding: .utf8)

            let received = await Self.firstElement(of: signals, timeout: .seconds(10))
            XCTAssertNotNil(received, "TrashChanged should fire after the Trash changes")
            XCTAssertEqual(received?.member, "TrashChanged")
        }
    }

    /// The first element of `stream`, or `nil` if `timeout` elapses first.
    private static func firstElement(of stream: AsyncStream<DBusMessage>,
                                     timeout: Duration) async -> DBusMessage? {
        await withTaskGroup(of: DBusMessage?.self) { group in
            group.addTask {
                for await message in stream { return message }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Harness

    /// Runs a `TopDrawerService` on its own session-bus connection until the test
    /// cancels it. All backends are injectable; they default to the production ones
    /// except `trashDirectory`, which defaults to a temp subdirectory so a test never
    /// watches (or counts) the developer's real Trash.
    private func startServer(volumeSource: VolumeSnapshotProviding = ProcMounts(),
                             trashService: TrashServicing = GioTrashService(),
                             trashDirectory: URL? = nil,
                             ejector: @escaping @Sendable (LinuxVolume) -> Bool = VolumeEjector.eject) {
        let source = LauncherDocumentSource(url: launcherURL)
        let trashDir = trashDirectory ?? tempDir.appendingPathComponent("trash", isDirectory: true)
        serverTask = Task {
            do {
                try await DBusClient.withSessionBus(auth: .external(userID: String(getuid()))) { connection in
                    let service = TopDrawerService(
                        source: source, volumeSource: volumeSource, trashService: trashService,
                        trashDirectory: trashDir, ejector: ejector)
                    try await service.run(on: connection, watchInterval: .milliseconds(200))
                    // Keep the export alive for the duration of the test; tearDown cancels us.
                    try await Task.sleep(for: .seconds(30))
                }
            } catch is CancellationError {
                // Expected: tearDown cancels us to tear down the export.
            } catch {
                // A real startup failure (e.g. RequestName lost the name) should fail the
                // test loudly here, not surface later as a 10-second `callReady` timeout.
                // But once tearDown has cancelled us, the cancellation can unwind through
                // the dbus/NIO stack as a *wrapped* error (a closed channel, a reset
                // connection) rather than a clean `CancellationError`, so gate on
                // `Task.isCancelled`: a genuine failure happens before any cancel (isCancelled
                // == false); post-cancel noise (isCancelled == true) is expected teardown.
                if !Task.isCancelled {
                    XCTFail("server task failed: \(error)")
                }
            }
        }
    }

    private func withClient(_ body: @escaping @Sendable (DBusClient.Connection) async throws -> Void) async throws {
        try await DBusClient.withSessionBus(auth: .external(userID: String(getuid()))) { client in
            try await body(client)
        }
    }

    /// One method call to our service, returning the reply message.
    private func call(_ client: DBusClient.Connection, method: String,
                      body: [DBusValue] = []) async throws -> DBusMessage {
        let reply = try await client.send(
            .createMethodCall(
                destination: TopDrawerService.busName,
                path: TopDrawerService.objectPath,
                interface: TopDrawerService.interfaceName,
                method: method, body: body),
            timeoutNanoseconds: 5_000_000_000)
        return try XCTUnwrap(reply, "no reply to \(method)")
    }

    /// Calls `method`, retrying while the name has no owner yet (the server races the
    /// client at start-up), until a real method return arrives or we give up.
    @discardableResult
    private func callReady(_ client: DBusClient.Connection, method: String) async throws -> DBusMessage {
        for _ in 0..<40 {
            let reply = try await call(client, method: method)
            if reply.messageType == .methodReturn { return reply }
            try await Task.sleep(for: .milliseconds(250))   // ServiceUnknown while the server starts
        }
        XCTFail("service never became ready on \(TopDrawerService.busName)")
        return try await call(client, method: method)
    }
}

// MARK: - Test doubles

/// A fixed volume snapshot, so `GetVolumes` is deterministic without a real `/proc`.
private struct FakeVolumeSource: VolumeSnapshotProviding {
    let list: [LinuxVolume]
    init(_ list: [LinuxVolume]) { self.list = list }
    func volumes() -> [LinuxVolume] { list }
}

/// A fixed trash count, so `GetTrashState` is deterministic without a real Trash.
private struct FakeTrashService: TrashServicing {
    let count: Int
    func trashCount() -> Int { count }
    func trashIsEmpty() -> Bool { count == 0 }
    func trash(_ urls: [URL]) -> Bool { true }
    func emptyTrash() -> Bool { true }
}
#endif
