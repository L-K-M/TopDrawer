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
            XCTAssertEqual(launch.body.first?.boolean, false, "Launch of an item id absent from the document returns false")

            let dropped = try await self.call(
                client, method: "AddDroppedURIs",
                body: [.string("tab"), .array([.string("file:///tmp/x")])])
            XCTAssertEqual(dropped.body.first?.boolean, false, "AddDroppedURIs is still a stub (document mutation → LP-23)")
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
                           "GetRecents", "Launch", "OpenWith", "Reveal", "GetRunningAppIDs",
                           "AddDroppedURIs"] {
                XCTAssertTrue(xml.contains(#"method name="\#(method)""#), "missing \(method) in \(xml)")
            }
            for signal in ["DocumentChanged", "VolumesChanged", "TrashChanged", "RecentsChanged",
                           "RunningAppsChanged"] {
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
        // A non-ejectable entry GetVolumes also returns (a Dropbox folder) — the server
        // must refuse to hand it to the ejector.
        let folder = LinuxVolume(id: "/home/alice/Dropbox", name: "Dropbox", path: "/home/alice/Dropbox",
                                 kind: .cloud, device: "/home/alice/Dropbox", ejectable: false)
        let spy = EjectSpy()
        startServer(volumeSource: FakeVolumeSource([volume, folder]), ejector: spy.eject)
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let unknown = try await self.call(client, method: "Eject", body: [.string("/no/such")])
            XCTAssertEqual(unknown.body.first?.boolean, false, "an unknown id ejects nothing")

            let nonEjectable = try await self.call(client, method: "Eject", body: [.string("/home/alice/Dropbox")])
            XCTAssertEqual(nonEjectable.body.first?.boolean, false, "a non-ejectable volume is refused")

            let known = try await self.call(client, method: "Eject", body: [.string("/media/alice/USB")])
            XCTAssertEqual(known.body.first?.boolean, true, "a known ejectable id is handed to the ejector")
            XCTAssertEqual(spy.recordedDevices, ["/dev/sdb1"],
                           "only the ejectable volume reaches the ejector — not the unknown or non-ejectable ids")
        }
    }

    func testTrashChangedFiresWhenTheTrashDirectoryChanges() async throws {
        let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
        let files = trashDir.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        // The signal gates on the served count, so point the service at the same temp
        // Trash the watch fires on — a file there then changes both together.
        startServer(trashService: DirCountingTrashService(directory: trashDir), trashDirectory: trashDir)
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

            // Trash files repeatedly (each new file bumps the count → a fresh
            // TrashChanged) while waiting, so a single emit that races the bus
            // subscription becoming effective can't make this flaky.
            let writer = Self.repeatedlyCreateFiles(in: files)
            let received = await Self.firstElement(of: signals, timeout: .seconds(10))
            writer.cancel()
            XCTAssertNotNil(received, "TrashChanged should fire after the Trash changes")
            XCTAssertEqual(received?.member, "TrashChanged")
        }
    }

    /// Fresh profile: the Trash `files/` dir doesn't exist when the daemon starts.
    /// inotify can't attach to it yet, so the poll backstop must still deliver
    /// `TrashChanged` once the directory and an item appear.
    func testTrashChangedFiresOnAFreshProfileWhenFilesDirAppearsLater() async throws {
        let trashDir = tempDir.appendingPathComponent("fresh-trash", isDirectory: true)
        let files = trashDir.appendingPathComponent("files", isDirectory: true)
        // Note: files/ (and trashDir) deliberately do NOT exist yet.
        startServer(trashService: DirCountingTrashService(directory: trashDir), trashDirectory: trashDir)
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            _ = try await client.send(
                .createMethodCall(
                    destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                    interface: "org.freedesktop.DBus", method: "AddMatch",
                    body: [.string("type='signal',interface='\(TopDrawerService.interfaceName)',member='TrashChanged'")]),
                timeoutNanoseconds: 5_000_000_000)
            let signals = await client.subscribeToSignal(
                interface: TopDrawerService.interfaceName, member: "TrashChanged")

            try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
            let writer = Self.repeatedlyCreateFiles(in: files)
            let received = await Self.firstElement(of: signals, timeout: .seconds(10))
            writer.cancel()
            XCTAssertNotNil(received, "the poll backstop should deliver TrashChanged on a fresh profile")
        }
    }

    // MARK: - LP-18: recents / fresh

    private func writeDocument(_ json: String) throws {
        try json.write(to: launcherURL, atomically: true, encoding: .utf8)
    }

    private func recentsList(_ reply: DBusMessage) throws -> [[String: Any]] {
        let json = try XCTUnwrap(reply.body.first?.string)
        let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        return try XCTUnwrap(root?["recents"] as? [[String: Any]])
    }

    func testGetRecentsServesSystemRecentsForARecentsTab() async throws {
        try writeDocument(#"{"version":1,"tabs":[{"id":"rec","kind":"recents","recentsSource":"system"}]}"#)
        let hit = RecentFileHit(url: URL(fileURLWithPath: "/home/alice/report.pdf"),
                                name: "report.pdf", date: Date(timeIntervalSince1970: 1_000_000))
        startServer(recentsProvider: FakeRecentsProvider(system: [hit]))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let list = try self.recentsList(try await self.call(client, method: "GetRecents", body: [.string("rec")]))
            XCTAssertEqual(list.count, 1)
            XCTAssertEqual(list.first?["name"] as? String, "report.pdf")
            XCTAssertEqual(list.first?["path"] as? String, "/home/alice/report.pdf")
            // Pin the documented wire contract: `date` is Unix epoch seconds, not a
            // string, not milliseconds. `as? Double` is robust to Int/Double NSNumber
            // bridging (same cast the encode-shape unit test uses).
            XCTAssertEqual(list.first?["date"] as? Double, 1_000_000,
                           "date must be Unix epoch seconds as a JSON number — not a string, not milliseconds")
        }
    }

    func testGetRecentsServesFreshForAFreshTab() async throws {
        try writeDocument(#"{"version":1,"tabs":[{"id":"fr","kind":"fresh"}]}"#)
        let hit = RecentFileHit(url: URL(fileURLWithPath: "/home/alice/Downloads/new.zip"),
                                name: "new.zip", date: Date(timeIntervalSince1970: 2_000_000))
        startServer(recentsProvider: FakeRecentsProvider(freshHits: [hit]))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let list = try self.recentsList(try await self.call(client, method: "GetRecents", body: [.string("fr")]))
            XCTAssertEqual(list.first?["name"] as? String, "new.zip")
        }
    }

    func testGetRecentsIsEmptyForNonRecentsAndMacDringOnlyTabs() async throws {
        try writeDocument(#"""
        {"version":1,"tabs":[{"id":"items","kind":"items"},{"id":"mac","kind":"recents","recentsSource":"macDring"}]}
        """#)
        let hit = RecentFileHit(url: URL(fileURLWithPath: "/x"), name: "x", date: Date(timeIntervalSince1970: 1))
        startServer(recentsProvider: FakeRecentsProvider(system: [hit], freshHits: [hit]))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let itemsList = try self.recentsList(try await self.call(client, method: "GetRecents", body: [.string("items")]))
            XCTAssertTrue(itemsList.isEmpty, "an items tab has no recents")
            let macList = try self.recentsList(try await self.call(client, method: "GetRecents", body: [.string("mac")]))
            XCTAssertTrue(macList.isEmpty, "a macDring recents tab is empty when nothing has been launched (empty recorder)")
            // A tab id absent from the document hits the lookup-miss path (not a kind
            // mismatch); it too returns {"recents":[]}, matching the README's "any other tab".
            let unknownList = try self.recentsList(try await self.call(client, method: "GetRecents", body: [.string("does-not-exist")]))
            XCTAssertTrue(unknownList.isEmpty, #"an unknown tab id also returns {"recents":[]}"#)
        }
    }

    // MARK: - LP-19: launching + recents recording

    private static let oneItemDoc = #"{"version":1,"tabs":[{"id":"t","kind":"items","items":[{"id":"i1","kind":"file","displayName":"Doc","url":"file:///home/a/doc.txt"}]}]}"#

    func testLaunchResolvesTheItemLaunchesAndRecords() async throws {
        try writeDocument(Self.oneItemDoc)
        let launcher = FakeLauncher(launchResult: true)
        let recorder = FakeRecorder()
        startServer(launcher: launcher, recorder: recorder)
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let reply = try await self.call(client, method: "Launch", body: [.string("i1")])
            XCTAssertEqual(reply.body.first?.boolean, true)
            XCTAssertEqual(launcher.launched.map(\.id), ["i1"])
            // A successful launch records into recents (the macDring source).
            XCTAssertEqual(recorder.recorded.map { $0.url.path }, ["/home/a/doc.txt"])
            XCTAssertEqual(recorder.recorded.first?.kind, "file")
            XCTAssertEqual(recorder.recorded.first?.name, "Doc")
            // The service stamps a real launch timestamp (not a placeholder).
            let recordedDate = try XCTUnwrap(recorder.recorded.first?.date)
            XCTAssertLessThan(abs(recordedDate.timeIntervalSinceNow), 60)
        }
    }

    func testLaunchOfUnknownItemDoesNotLaunchOrRecord() async throws {
        try writeDocument(#"{"version":1,"tabs":[{"id":"t","kind":"items","items":[]}]}"#)
        let launcher = FakeLauncher()
        let recorder = FakeRecorder()
        startServer(launcher: launcher, recorder: recorder)
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let reply = try await self.call(client, method: "Launch", body: [.string("nope")])
            XCTAssertEqual(reply.body.first?.boolean, false)
            XCTAssertTrue(launcher.launched.isEmpty)
            XCTAssertTrue(recorder.recorded.isEmpty)
        }
    }

    func testFailedLaunchIsNotRecorded() async throws {
        try writeDocument(Self.oneItemDoc)
        let launcher = FakeLauncher(launchResult: false)
        let recorder = FakeRecorder()
        startServer(launcher: launcher, recorder: recorder)
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let reply = try await self.call(client, method: "Launch", body: [.string("i1")])
            XCTAssertEqual(reply.body.first?.boolean, false)
            XCTAssertEqual(launcher.launched.map(\.id), ["i1"])   // attempted…
            XCTAssertTrue(recorder.recorded.isEmpty)              // …but a failure isn't recorded
        }
    }

    func testOpenWithDispatchesToTheLauncher() async throws {
        let launcher = FakeLauncher()
        startServer(launcher: launcher)
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let reply = try await self.call(client, method: "OpenWith",
                body: [.string("org.gnome.gedit"), .array([.string("file:///a"), .string("file:///b")])])
            XCTAssertEqual(reply.body.first?.boolean, true)
            XCTAssertEqual(launcher.openWithCalls.first?.id, "org.gnome.gedit")
            XCTAssertEqual(launcher.openWithCalls.first?.uris, ["file:///a", "file:///b"])
        }
    }

    func testOpenWithReturnsTheLauncherResultOnFailure() async throws {
        startServer(launcher: FakeLauncher(openWithResult: false))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let reply = try await self.call(client, method: "OpenWith",
                body: [.string("no.such.app"), .array([.string("file:///a")])])
            XCTAssertEqual(reply.body.first?.boolean, false)
        }
    }

    func testRevealDispatchesToTheLauncher() async throws {
        let launcher = FakeLauncher()
        startServer(launcher: launcher)
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let reply = try await self.call(client, method: "Reveal", body: [.string("file:///home/a/x.pdf")])
            XCTAssertEqual(reply.body.first?.boolean, true)
            XCTAssertEqual(launcher.revealed, ["file:///home/a/x.pdf"])
        }
    }

    func testRevealReturnsTheLauncherResultOnFailure() async throws {
        startServer(launcher: FakeLauncher(revealResult: false))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let reply = try await self.call(client, method: "Reveal", body: [.string("file:///home/a/x.pdf")])
            XCTAssertEqual(reply.body.first?.boolean, false)
        }
    }

    func testLaunchEmitsRecentsChangedForMacDringTabs() async throws {
        // An items tab holds the launchable item; a macDring recents tab must be notified.
        try writeDocument(#"""
        {"version":1,"tabs":[{"id":"rec","kind":"recents","recentsSource":"macDring"},{"id":"t","kind":"items","items":[{"id":"i1","kind":"file","displayName":"Doc","url":"file:///home/a/doc.txt"}]}]}
        """#)
        startServer(launcher: FakeLauncher(launchResult: true), recorder: FakeRecorder())
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            _ = try await client.send(
                .createMethodCall(
                    destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                    interface: "org.freedesktop.DBus", method: "AddMatch",
                    body: [.string("type='signal',interface='\(TopDrawerService.interfaceName)',member='RecentsChanged'")]),
                timeoutNanoseconds: 5_000_000_000)
            let signals = await client.subscribeToSignal(
                interface: TopDrawerService.interfaceName, member: "RecentsChanged")
            _ = try await self.call(client, method: "Launch", body: [.string("i1")])
            let received = await Self.firstElement(of: signals, timeout: .seconds(10))
            XCTAssertEqual(received?.body.first?.string, "rec",
                           "a recorded launch notifies the macDring recents tab")
        }
    }

    func testGetRecentsServesTheMacDringLaunchHistory() async throws {
        // A macDring-source recents tab (the default) now serves the recorded launch history.
        try writeDocument(#"{"version":1,"tabs":[{"id":"rec","kind":"recents","recentsSource":"macDring"}]}"#)
        let hit = RecentFileHit(url: URL(fileURLWithPath: "/home/a/opened.txt"),
                                name: "opened.txt", date: Date(timeIntervalSince1970: 3_000_000))
        startServer(recorder: FakeRecorder(canned: [hit]))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let list = try self.recentsList(try await self.call(client, method: "GetRecents", body: [.string("rec")]))
            XCTAssertEqual(list.first?["name"] as? String, "opened.txt")
            XCTAssertEqual(list.first?["path"] as? String, "/home/a/opened.txt")
        }
    }

    func testGetRecentsBothSourceMergesSystemAndMacDring() async throws {
        try writeDocument(#"{"version":1,"tabs":[{"id":"rec","kind":"recents","recentsSource":"both"}]}"#)
        let sys = RecentFileHit(url: URL(fileURLWithPath: "/sys.txt"), name: "sys.txt",
                                date: Date(timeIntervalSince1970: 1_000))
        let mac = RecentFileHit(url: URL(fileURLWithPath: "/mac.txt"), name: "mac.txt",
                                date: Date(timeIntervalSince1970: 2_000))
        startServer(recentsProvider: FakeRecentsProvider(system: [sys]),
                    recorder: FakeRecorder(canned: [mac]))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let list = try self.recentsList(try await self.call(client, method: "GetRecents", body: [.string("rec")]))
            // Both sources fold in, newest (mac, t=2000) first.
            XCTAssertEqual(list.compactMap { $0["name"] as? String }, ["mac.txt", "sys.txt"])
        }
    }

    func testGetRecentsBothSourceDedupesTheSamePath() async throws {
        // The common case: a launched file (macDring) that's also in the system xbel.
        try writeDocument(#"{"version":1,"tabs":[{"id":"rec","kind":"recents","recentsSource":"both"}]}"#)
        let sys = RecentFileHit(url: URL(fileURLWithPath: "/same.txt"), name: "same.txt",
                                date: Date(timeIntervalSince1970: 1_000))
        let mac = RecentFileHit(url: URL(fileURLWithPath: "/same.txt"), name: "mac-same.txt",
                                date: Date(timeIntervalSince1970: 2_000))
        startServer(recentsProvider: FakeRecentsProvider(system: [sys]),
                    recorder: FakeRecorder(canned: [mac]))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let list = try self.recentsList(try await self.call(client, method: "GetRecents", body: [.string("rec")]))
            XCTAssertEqual(list.count, 1, "a file present in both sources appears once")
            XCTAssertEqual(list.first?["name"] as? String, "mac-same.txt",
                           "the newer macDring record wins the URL dedupe (newest-first)")
        }
    }

    // MARK: - LP-19b: running apps

    func testGetRunningAppIDsReturnsTheScannedSet() async throws {
        startServer(runningApps: FakeRunningApps(ids: ["com.example.App", "org.gnome.Nautilus"]))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let reply = try await self.call(client, method: "GetRunningAppIDs")
            let json = try XCTUnwrap(reply.body.first?.string)
            let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            // A set semantically, so compare order-insensitively.
            XCTAssertEqual((root?["appIDs"] as? [String])?.sorted(),
                           ["com.example.App", "org.gnome.Nautilus"])
        }
    }

    func testGetRunningAppIDsIsEmptyWhenNothingRuns() async throws {
        startServer(runningApps: FakeRunningApps(ids: []))
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let reply = try await self.call(client, method: "GetRunningAppIDs")
            // Unwrapping `.string` also proves the reply is a JSON *string* (`s`), not a
            // mis-signed empty native D-Bus array; parse rather than pin exact formatting.
            let json = try XCTUnwrap(reply.body.first?.string)
            let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            XCTAssertEqual(root?["appIDs"] as? [String], [], json)
        }
    }

    func testRunningAppsChangedFiresWhenTheSetChanges() async throws {
        let apps = MutableRunningApps([])
        startServer(runningApps: apps)
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            let addMatch = try await client.send(
                .createMethodCall(
                    destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                    interface: "org.freedesktop.DBus", method: "AddMatch",
                    body: [.string("type='signal',interface='\(TopDrawerService.interfaceName)',member='RunningAppsChanged'")]),
                timeoutNanoseconds: 5_000_000_000)
            // A rejected match rule would otherwise surface only as the 10s timeout below.
            XCTAssertEqual(addMatch?.messageType, .methodReturn, "the bus rejected the AddMatch rule")
            let signals = await client.subscribeToSignal(
                interface: TopDrawerService.interfaceName, member: "RunningAppsChanged")
            // A new app appears — the /proc poll should notice and broadcast.
            apps.set(["org.gnome.Nautilus"])
            let received = await Self.firstElement(of: signals, timeout: .seconds(10))
            XCTAssertEqual(received?.member, "RunningAppsChanged")
        }
    }

    func testRecentsChangedFiresWhenAFreshScopeChanges() async throws {
        try writeDocument(#"{"version":1,"tabs":[{"id":"fr","kind":"fresh"}]}"#)
        let scope = tempDir.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
        startServer(freshScopes: [scope])
        try await withClient { client in
            _ = try await self.callReady(client, method: "Ping")
            _ = try await client.send(
                .createMethodCall(
                    destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                    interface: "org.freedesktop.DBus", method: "AddMatch",
                    body: [.string("type='signal',interface='\(TopDrawerService.interfaceName)',member='RecentsChanged'")]),
                timeoutNanoseconds: 5_000_000_000)
            let signals = await client.subscribeToSignal(
                interface: TopDrawerService.interfaceName, member: "RecentsChanged")

            // A file arriving in the Fresh scope should fire RecentsChanged for the fresh tab.
            let writer = Self.repeatedlyCreateFiles(in: scope)
            let received = await Self.firstElement(of: signals, timeout: .seconds(10))
            writer.cancel()
            XCTAssertEqual(received?.member, "RecentsChanged")
            XCTAssertEqual(received?.body.first?.string, "fr", "the affected fresh tab's id is carried")
        }
    }

    /// Creates a fresh file in `directory` every 300ms until cancelled. Used by both the
    /// Trash tests (each new file bumps the trashed-item count) and the fresh-scope test
    /// (each new file is a Fresh arrival), so a single signal emit that races the bus
    /// subscription setup can't make the signal tests flaky (the next write emits again).
    private static func repeatedlyCreateFiles(in directory: URL) -> Task<Void, Never> {
        Task {
            for i in 0..<50 {
                if Task.isCancelled { break }
                try? "gone".write(to: directory.appendingPathComponent("deleted-\(i).txt"),
                                  atomically: true, encoding: .utf8)
                try? await Task.sleep(for: .milliseconds(300))
            }
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
                             trashService: TrashServicing = FakeTrashService(count: 0),
                             trashDirectory: URL? = nil,
                             ejector: @escaping @Sendable (LinuxVolume) -> Bool = VolumeEjector.eject,
                             recentsProvider: RecentsProviding = FakeRecentsProvider(),
                             launcher: LinuxLaunching = FakeLauncher(),
                             recorder: RecentsRecording = FakeRecorder(),
                             runningApps: RunningAppsScanning = FakeRunningApps(),
                             xbelLocation: URL? = nil,
                             freshScopes: [URL]? = nil) {
        let source = LauncherDocumentSource(url: launcherURL)
        let trashDir = trashDirectory ?? tempDir.appendingPathComponent("trash", isDirectory: true)
        // Default the recents watches at hermetic temp paths so a test never polls the
        // developer's real recently-used.xbel or watches their real Downloads/Desktop.
        let xbel = xbelLocation ?? tempDir.appendingPathComponent("recently-used.xbel")
        // Create the hermetic default scope so the default watch target always exists
        // (a caller-supplied freshScopes is left as-is).
        let defaultScope = tempDir.appendingPathComponent("fresh-scope", isDirectory: true)
        try? FileManager.default.createDirectory(at: defaultScope, withIntermediateDirectories: true)
        let scopes = freshScopes ?? [defaultScope]
        serverTask = Task {
            do {
                try await DBusClient.withSessionBus(auth: .external(userID: String(getuid()))) { connection in
                    let service = TopDrawerService(
                        source: source, volumeSource: volumeSource, trashService: trashService,
                        trashDirectory: trashDir, ejector: ejector,
                        recentsProvider: recentsProvider, launcher: launcher, recorder: recorder,
                        runningApps: runningApps, xbelLocation: xbel, freshScopes: scopes)
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

/// Counts a specific temp Trash directory — lets the `TrashChanged` test drive the
/// served count (which the signal gates on) by writing into that directory.
private struct DirCountingTrashService: TrashServicing {
    let directory: URL
    func trashCount() -> Int { TrashLocation.count(trashDirectory: directory) }
    func trashIsEmpty() -> Bool { trashCount() == 0 }
    func trash(_ urls: [URL]) -> Bool { true }
    func emptyTrash() -> Bool { true }
}

/// Fixed recents/fresh snapshots, so `GetRecents` is deterministic without a real
/// `recently-used.xbel` or filesystem scan.
private struct FakeRecentsProvider: RecentsProviding {
    var system: [RecentFileHit] = []
    var freshHits: [RecentFileHit] = []
    func systemRecents(limit: Int) -> [RecentFileHit] { Array(system.prefix(limit)) }
    func fresh(limit: Int) -> [RecentFileHit] { Array(freshHits.prefix(limit)) }
}

/// Records what `Launch`/`OpenWith`/`Reveal` dispatch, so the D-Bus wiring is testable
/// without shelling to `gio`. Thread-safe: the handler runs off the test's thread.
final class FakeLauncher: LinuxLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var _launched: [LauncherItem] = []
    private var _openWith: [(id: String, uris: [String])] = []
    private var _revealed: [String] = []
    private let launchResult: Bool
    private let openWithResult: Bool
    private let revealResult: Bool

    init(launchResult: Bool = true, openWithResult: Bool = true, revealResult: Bool = true) {
        self.launchResult = launchResult
        self.openWithResult = openWithResult
        self.revealResult = revealResult
    }

    var launched: [LauncherItem] { lock.lock(); defer { lock.unlock() }; return _launched }
    var openWithCalls: [(id: String, uris: [String])] { lock.lock(); defer { lock.unlock() }; return _openWith }
    var revealed: [String] { lock.lock(); defer { lock.unlock() }; return _revealed }

    func launch(_ item: LauncherItem) -> Bool {
        lock.lock(); _launched.append(item); lock.unlock(); return launchResult
    }
    func openWith(desktopID: String, uris: [String]) -> Bool {
        lock.lock(); _openWith.append((desktopID, uris)); lock.unlock(); return openWithResult
    }
    func reveal(uri: String) -> Bool {
        lock.lock(); _revealed.append(uri); lock.unlock(); return revealResult
    }
}

/// Collects recorded launches and serves canned history, so recents recording/serving is
/// testable without touching the global `RecentsStore`/`UserDefaults`.
final class FakeRecorder: RecentsRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var _recorded: [(url: URL, kind: String, name: String, date: Date)] = []
    private let canned: [RecentFileHit]

    init(canned: [RecentFileHit] = []) { self.canned = canned }

    var recorded: [(url: URL, kind: String, name: String, date: Date)] {
        lock.lock(); defer { lock.unlock() }; return _recorded
    }

    func record(url: URL, kind: String, name: String, date: Date) async {
        lock.lock(); _recorded.append((url, kind, name, date)); lock.unlock()
    }
    func recents(limit: Int) async -> [RecentFileHit] { Array(canned.prefix(limit)) }
}

/// A fixed running-apps set, so `GetRunningAppIDs` is deterministic without a real `/proc`.
private struct FakeRunningApps: RunningAppsScanning {
    var ids: [String] = []
    func runningAppIDs() -> [String]? { ids }
}

/// A mutable running-apps set the `RunningAppsChanged` test flips after subscribing, to
/// drive the poll. Thread-safe: the watch loop reads it off the test's thread.
final class MutableRunningApps: RunningAppsScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var _ids: [String]
    init(_ ids: [String] = []) { _ids = ids }
    func set(_ ids: [String]) { lock.lock(); _ids = ids; lock.unlock() }
    func runningAppIDs() -> [String]? { lock.lock(); defer { lock.unlock() }; return _ids }
}

/// Records every volume handed to the ejector, so a test can prove the call happened
/// (not just that a lookup succeeded). Thread-safe: the D-Bus handler runs the ejector
/// off the test's thread.
final class EjectSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [String] = []

    var recordedDevices: [String] {
        lock.lock(); defer { lock.unlock() }
        return devices
    }

    func eject(_ volume: LinuxVolume) -> Bool {
        lock.lock(); defer { lock.unlock() }
        devices.append(volume.device)
        return volume.device == "/dev/sdb1"
    }
}
#endif
