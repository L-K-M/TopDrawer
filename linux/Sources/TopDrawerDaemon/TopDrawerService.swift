#if os(Linux)
import Foundation
import DBUS
import Logging
import MacDring

/// The Top Drawer daemon's D-Bus service.
///
/// Exports one object, `/ch/lkmc/TopDrawer`, implementing the `ch.lkmc.TopDrawer1`
/// interface on the **session** bus and claims the well-known name
/// `ch.lkmc.TopDrawer`:
/// - `Ping() -> s` — liveness probe (the LP-16 acceptance smoke test).
/// - `GetDocument() -> s` — the launcher JSON, served verbatim from disk.
/// - `GetVolumes() -> s` — the classified mounted volumes as JSON (LP-17).
/// - `Eject(s volumeID) -> b` — unmount/power-off a volume by its id (LP-17).
/// - `GetTrashState() -> b u` — whether the Trash is empty, and its item count (LP-17).
/// - `GetRecents(s tabID) -> s` — a Recents/Fresh tab's live contents as JSON (LP-18).
/// - `Launch(s itemID) -> b` — stub; returns `false` (real launching is LP-19).
/// - `AddDroppedURIs(s tabID, as uris) -> b` — stub; returns `false` (drops are LP-19).
/// - signal `DocumentChanged()` — the launcher file changed on disk.
/// - signal `VolumesChanged()` — the set of mounted volumes changed (LP-17).
/// - signal `TrashChanged()` — the Trash contents changed (LP-17).
/// - signal `RecentsChanged(s tabID)` — a Recents/Fresh tab's contents changed (LP-18).
///
/// `wendylabsinc/dbus` exposes no `RequestName` helper and does not auto-route
/// inbound calls, so this type does both itself: it registers a message handler that
/// forwards to a `DBusObjectServer`, and calls `org.freedesktop.DBus.RequestName`
/// directly to claim the name.
public actor TopDrawerService {

    public static let busName = "ch.lkmc.TopDrawer"
    public static let objectPath = "/ch/lkmc/TopDrawer"
    public static let interfaceName = "ch.lkmc.TopDrawer1"
    /// Reported by `Ping`; bump alongside the interface as the daemon grows.
    public static let version = "0.3.0"

    /// How many entries `GetRecents` returns per tab kind.
    private static let recentsLimit = 50
    private static let freshLimit = 40

    private let source: LauncherDocumentSource
    private let volumeSource: VolumeSnapshotProviding
    private let trashService: TrashServicing
    private let trashDirectory: URL
    private let ejector: @Sendable (LinuxVolume) -> Bool
    private let recentsProvider: RecentsProviding
    private let xbelLocation: URL
    private let freshScopes: [URL]
    private let logger: Logger
    private var connection: DBusClient.Connection?
    private var lastModified: Date?
    private var lastVolumes: [LinuxVolume] = []
    private var lastTrashCount: Int = 0
    private var lastXbelModified: Date?
    private var watchTask: Task<Void, Never>?
    private var trashWatcher: INotifyWatcher?
    private var freshWatchers: [INotifyWatcher] = []

    /// - Parameters:
    ///   - volumeSource: the mounted-volume snapshot source (`/proc` in production).
    ///   - trashService: backs `GetTrashState` (count + empty).
    ///   - trashDirectory: the freedesktop Trash directory watched for `TrashChanged`
    ///     (its `files/` count gates emission). Defaults to the live `$XDG_DATA_HOME`.
    ///   - ejector: performs an eject; injectable so tests don't shell out.
    ///   - recentsProvider: backs `GetRecents` (system recents + fresh scan).
    ///   - xbelLocation: the `recently-used.xbel` polled for `RecentsChanged` on Recents
    ///     tabs (inotify watches directories, not this single file). Defaults to
    ///     `$XDG_DATA_HOME/recently-used.xbel`.
    ///   - freshScopes: the landing-zone directories watched for `RecentsChanged` on
    ///     Fresh tabs. Defaults to Downloads/Desktop/Documents.
    public init(source: LauncherDocumentSource,
                volumeSource: VolumeSnapshotProviding = ProcMounts(),
                trashService: TrashServicing = GioTrashService(),
                trashDirectory: URL = TrashLocation.directory(
                    environment: ProcessInfo.processInfo.environment,
                    home: FileManager.default.homeDirectoryForCurrentUser),
                ejector: @escaping @Sendable (LinuxVolume) -> Bool = VolumeEjector.eject,
                recentsProvider: RecentsProviding? = nil,
                xbelLocation: URL = RecentlyUsedFile.location(
                    environment: ProcessInfo.processInfo.environment,
                    home: FileManager.default.homeDirectoryForCurrentUser),
                freshScopes: [URL] = FreshLister.scopes(),
                logger: Logger = Logger(label: "topdrawerd")) {
        self.source = source
        self.volumeSource = volumeSource
        self.trashService = trashService
        self.trashDirectory = trashDirectory
        self.ejector = ejector
        self.recentsProvider = recentsProvider
            ?? LinuxRecentsProvider(xbelURL: xbelLocation, freshScopes: freshScopes)
        self.xbelLocation = xbelLocation
        self.freshScopes = freshScopes
        self.logger = logger
    }

    /// Builds and exports the `ch.lkmc.TopDrawer1` object on `connection`, routes
    /// inbound calls to it, claims the bus name, and starts watching the launcher
    /// file. Returns once set up — the caller keeps the process (or, in tests, the
    /// connection scope) alive. Throws if the name is already owned.
    public func run(on connection: DBusClient.Connection,
                    watchInterval: Duration = .seconds(2)) async throws {
        self.connection = connection
        // `DBusObjectServer` replies through `DBusServerConnection.send`, whose contract
        // is fire-and-forget — but the real `Connection.send(_:)` waits for a reply, so a
        // server replying through it would block its own handler forever (the library only
        // ever tests the server against a fire-and-forget mock). Hand it an adapter that
        // writes replies without waiting.
        let server = DBusObjectServer(connection: FireAndForgetConnection(connection), logger: logger)

        var interface = DBusObjectServer.Interface(name: Self.interfaceName)
        interface.methods = makeMethods()
        interface.signals = [
            DBusObjectServer.Signal(name: "DocumentChanged"),
            DBusObjectServer.Signal(name: "VolumesChanged"),
            DBusObjectServer.Signal(name: "TrashChanged"),
            DBusObjectServer.Signal(name: "RecentsChanged", args: [.init(name: "tabID", type: "s")]),
        ]
        await server.export(DBusObjectServer.ExportedObject(path: Self.objectPath,
                                                            interfaces: [interface]))

        // The server doesn't hook the connection itself — feed it every inbound call.
        await connection.setMessageHandler { message in
            await server.handle(message: message)
        }

        try await claimBusName(on: connection)

        lastModified = source.modificationDate()
        lastVolumes = volumeSource.volumes()
        lastTrashCount = trashService.trashCount()
        lastXbelModified = xbelModificationDate()
        startTrashWatcher()
        startFreshWatchers()
        startWatching(interval: watchInterval)
    }

    /// Stops the file/volume watcher, the Trash watcher, and the Fresh watchers (the
    /// D-Bus export goes away with the connection).
    public func stop() {
        watchTask?.cancel()
        watchTask = nil
        trashWatcher?.stop()
        trashWatcher = nil
        freshWatchers.forEach { $0.stop() }
        freshWatchers = []
    }

    // MARK: - Methods

    private func makeMethods() -> [DBusObjectServer.Method] {
        let source = self.source
        let logger = self.logger
        let volumeSource = self.volumeSource
        let trashService = self.trashService
        let ejector = self.ejector
        let recentsProvider = self.recentsProvider
        return [
            DBusObjectServer.Method(
                name: "Ping",
                outputArgs: [.init(name: "pong", type: "s")]
            ) { _ in
                [.string("topdrawerd \(Self.version) alive")]
            },
            DBusObjectServer.Method(
                name: "GetDocument",
                outputArgs: [.init(name: "json", type: "s")]
            ) { _ in
                [.string(source.rawJSON())]
            },
            DBusObjectServer.Method(
                name: "GetVolumes",
                outputArgs: [.init(name: "json", type: "s")]
            ) { _ in
                [.string(Self.encodeVolumes(volumeSource.volumes()))]
            },
            DBusObjectServer.Method(
                name: "Eject",
                inputArgs: [.init(name: "volumeID", type: "s")],
                outputArgs: [.init(name: "ok", type: "b")]
            ) { context in
                let volumeID = context.arguments.first?.string ?? ""
                // Resolve the id (mount point) to a live volume, so a stale id from an
                // already-unmounted volume just fails rather than ejecting the wrong
                // device. Two guards with distinct logs so an operator auditing a false
                // reply can tell an unknown id from a policy rejection.
                guard let volume = volumeSource.volumes().first(where: { $0.id == volumeID }) else {
                    logger.info("Eject(\(volumeID)): no such volume")
                    return [.boolean(false)]
                }
                // Enforce `ejectable` server-side: GetVolumes returns non-ejectable
                // entries (e.g. a Dropbox folder), and a client mustn't be able to drive
                // one into VolumeEjector — reject it here rather than spawn subprocesses
                // doomed against a non-mount.
                guard volume.ejectable else {
                    logger.info("Eject(\(volumeID)): volume is not ejectable")
                    return [.boolean(false)]
                }
                return [.boolean(ejector(volume))]
            },
            DBusObjectServer.Method(
                name: "GetTrashState",
                outputArgs: [.init(name: "empty", type: "b"), .init(name: "count", type: "u")]
            ) { _ in
                // One observation, so `empty` and `count` can't contradict each other
                // (a file trashed between two calls). `clamping:` rather than a trapping
                // conversion — a negative error sentinel or an absurd count must not take
                // the daemon down.
                let count = trashService.trashCount()
                return [.boolean(count == 0), .uint32(UInt32(clamping: count))]
            },
            DBusObjectServer.Method(
                name: "GetRecents",
                inputArgs: [.init(name: "tabID", type: "s")],
                outputArgs: [.init(name: "json", type: "s")]
            ) { context in
                let tabID = context.arguments.first?.string ?? ""
                let hits = Self.recentsHits(forTab: tabID, document: source.rawJSON(),
                                            provider: recentsProvider)
                return [.string(Self.encodeRecents(hits))]
            },
            DBusObjectServer.Method(
                name: "Launch",
                inputArgs: [.init(name: "itemID", type: "s")],
                outputArgs: [.init(name: "ok", type: "b")]
            ) { context in
                let itemID = context.arguments.first?.string ?? ""
                logger.info("Launch(\(itemID)): not implemented in the LP-16 skeleton (lands in LP-19)")
                return [.boolean(false)]
            },
            DBusObjectServer.Method(
                name: "AddDroppedURIs",
                inputArgs: [.init(name: "tabID", type: "s"), .init(name: "uris", type: "as")],
                outputArgs: [.init(name: "ok", type: "b")]
            ) { context in
                let tabID = context.arguments.first?.string ?? ""
                let uris = context.arguments.dropFirst().first?.array?.compactMap(\.string) ?? []
                logger.info("AddDroppedURIs(\(tabID), \(uris.count) uris): not implemented yet (drops land in LP-19)")
                return [.boolean(false)]
            },
        ]
    }

    // MARK: - Bus name

    /// `org.freedesktop.DBus.RequestName` reply code for "we are the primary owner".
    private static let requestNameBecamePrimaryOwner: UInt32 = 1
    /// `DBUS_NAME_FLAG_DO_NOT_QUEUE` — fail rather than queue when the name is taken,
    /// so a second daemon reports the conflict instead of silently waiting.
    private static let doNotQueueFlag: UInt32 = 0x4

    private func claimBusName(on connection: DBusClient.Connection) async throws {
        // Use the two-arg (timeout) overload: the single-arg `connection.send(_:)`
        // collides with the `Send` actor property's `callAsFunction`, which returns a
        // serial, not the reply. A bounded wait also means a wedged bus can't hang start-up.
        let reply = try await connection.send(
            .createMethodCall(
                destination: "org.freedesktop.DBus",
                path: "/org/freedesktop/DBus",
                interface: "org.freedesktop.DBus",
                method: "RequestName",
                body: [.string(Self.busName), .uint32(Self.doNotQueueFlag)]),
            timeoutNanoseconds: 5_000_000_000)
        let code = reply?.body.first?.uint32
        guard code == Self.requestNameBecamePrimaryOwner else {
            throw TopDrawerServiceError.busNameUnavailable(name: Self.busName, replyCode: code)
        }
        logger.info("Owns D-Bus name \(Self.busName)")
    }

    // MARK: - Change watches

    /// Polls the launcher document's mtime and the mounted-volume set on the same
    /// interval. inotify can't watch `/proc`, so volumes are polled (a mount/unmount is
    /// rare and not latency-critical); the launcher file is polled for the same reason
    /// LP-16 chose to (a plain descriptor source misses the atomic-rename write). The
    /// Trash has its own inotify watch (`startTrashWatcher`).
    private func startWatching(interval: Duration) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                // Stop once the service is gone (e.g. a test's service goes out of scope
                // without an explicit stop()), rather than polling forever on `nil`.
                guard let self else { break }
                await self.checkForDocumentChange()
                await self.checkForVolumeChange()
                // Poll the Trash count too, as a guaranteed-delivery backstop to the
                // inotify watch: the watch lowers latency, but a poll can't be defeated
                // by an inotify edge case (the files/ dir not existing yet, the dir being
                // deleted and recreated). The count gate keeps it idempotent, so the two
                // sources never double-fire.
                await self.checkForTrashChange()
                // recently-used.xbel is a single file (inotify watches directories), and
                // it sits in the busy $XDG_DATA_HOME, so poll its mtime rather than watch
                // that whole directory.
                await self.checkForRecentsFileChange()
            }
        }
    }

    private func checkForDocumentChange() async {
        let current = source.modificationDate()
        guard current != lastModified else { return }
        lastModified = current
        await emitSignal("DocumentChanged")
    }

    private func checkForVolumeChange() async {
        let current = volumeSource.volumes()
        guard current != lastVolumes else { return }
        lastVolumes = current
        await emitSignal("VolumesChanged")
    }

    // MARK: - Trash watch

    /// The freedesktop Trash count changes without touching `/proc`, so it *can* be
    /// inotify-watched: an `INotifyWatcher` on the Trash directory (its `files/` appears
    /// on first use) fires `TrashChanged` when the count actually moves. Gating on the
    /// count avoids re-emitting for metadata-only churn.
    private func startTrashWatcher() {
        trashWatcher?.stop()   // a second start() (reconnect, tests) must not leak the fd
        let watched = trashDirectory.appendingPathComponent("files", isDirectory: true)
        let watcher = INotifyWatcher(directory: watched) { [weak self] in
            Task { await self?.checkForTrashChange() }
        }
        watcher.start()
        trashWatcher = watcher
    }

    private func checkForTrashChange() async {
        // Gate on the same count `GetTrashState` serves (`trashService`), so the signal
        // can never diverge from the reported state. In production the injected
        // `trashDirectory` the watch fires on and the service's own directory are the
        // same freedesktop Trash, so a file event maps to a count change here.
        let current = trashService.trashCount()
        guard current != lastTrashCount else { return }
        lastTrashCount = current
        await emitSignal("TrashChanged")
    }

    // MARK: - Recents / Fresh watches

    /// One `INotifyWatcher` per Fresh landing zone (Downloads/Desktop/Documents). These
    /// are real directories, so inotify fits: a file arriving fires `RecentsChanged` for
    /// every Fresh tab. (Recents' xbel is polled instead — see the watch loop.)
    private func startFreshWatchers() {
        freshWatchers.forEach { $0.stop() }
        freshWatchers = freshScopes.map { scope in
            let watcher = INotifyWatcher(directory: scope) { [weak self] in
                Task { await self?.emitRecentsChanged(forKind: "fresh") }
            }
            watcher.start()
            return watcher
        }
    }

    private func checkForRecentsFileChange() async {
        let current = xbelModificationDate()
        guard current != lastXbelModified else { return }
        lastXbelModified = current
        await emitRecentsChanged(forKind: "recents")
    }

    private func xbelModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: xbelLocation.path))?[.modificationDate] as? Date
    }

    /// Fires `RecentsChanged(tabID)` for every tab of `kind` in the current document, so
    /// the frontend refreshes exactly the affected tabs.
    private func emitRecentsChanged(forKind kind: String) async {
        let ids = LauncherTabs.all(in: source.rawJSON()).filter { $0.kind == kind }.map(\.id)
        for id in ids {
            await emitSignal("RecentsChanged", body: [.string(id)], signature: "s")
        }
    }

    // MARK: - Signals

    /// Emits `DocumentChanged` — kept for tests that exercise the signal path directly,
    /// without waiting on the file-watch interval.
    public func emitDocumentChanged() async { await emitSignal("DocumentChanged") }

    /// A `ch.lkmc.TopDrawer1` signal (optionally with a body). Fired through the `Send`
    /// actor (a signal expects no reply, unlike `connection.send(_:)` which would wait
    /// for one).
    private func emitSignal(_ name: String, body: [DBusValue] = [], signature: String? = nil) async {
        guard let connection else { return }
        let signal = DBusRequest.createSignal(
            path: Self.objectPath, interface: Self.interfaceName, name: name,
            body: body, signature: signature)
        let sender: DBusClient.Send = await connection.send
        do {
            _ = try await sender.send(signal)
        } catch {
            logger.debug("Couldn't emit \(name): \(error)")
        }
    }

    // MARK: - JSON

    /// `{"volumes":[…]}` — a stable envelope so the field can gain siblings later without
    /// the frontend re-parsing a bare array. Deterministic key order (sorted) keeps the
    /// output diffable in tests.
    static func encodeVolumes(_ volumes: [LinuxVolume]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        struct Envelope: Encodable { let volumes: [LinuxVolume] }
        guard let data = try? encoder.encode(Envelope(volumes: volumes)) else { return #"{"volumes":[]}"# }
        return String(decoding: data, as: UTF8.self)
    }

    /// The hits a `GetRecents(tabID)` should serve, resolved from the tab's kind in the
    /// launcher document. Static + injected provider so it's unit-testable without a bus.
    static func recentsHits(forTab tabID: String, document json: String,
                            provider: RecentsProviding) -> [RecentFileHit] {
        guard let tab = LauncherTabs.find(id: tabID, in: json) else { return [] }
        switch tab.kind {
        case "recents":
            // LP-18 serves the *system* recents (recently-used.xbel). The macDring launch
            // history (RecentsStore) is UserDefaults-backed and only populated by
            // launching, so its merge lands with LP-19; honor the recentsSource's system
            // part now. A macDring-only recents tab (the default) is therefore empty until
            // LP-19 — correct, since nothing has been launched yet.
            let source = tab.recentsSource ?? "macDring"
            let includesSystem = source == "system" || source == "both"
            return includesSystem ? provider.systemRecents(limit: recentsLimit) : []
        case "fresh":
            return provider.fresh(limit: freshLimit)
        default:
            return []   // not a recents/fresh tab
        }
    }

    /// `{"recents":[{path,name,date}]}` — same stable-envelope + sorted-keys shape as
    /// `encodeVolumes`. `date` is Unix epoch seconds.
    static func encodeRecents(_ hits: [RecentFileHit]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        struct Envelope: Encodable { let recents: [RecentEntry] }
        let entries = hits.map(RecentEntry.init)
        guard let data = try? encoder.encode(Envelope(recents: entries)) else { return #"{"recents":[]}"# }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Wraps a `DBusClient.Connection` so `DBusObjectServer` can send replies without
/// waiting for a reply-to-the-reply. `Connection.send(_:)` blocks until a reply
/// arrives (unless the request is flagged no-reply-expected, which method returns
/// aren't), so routing the server's replies through it deadlocks; the `Send` actor's
/// `send` just writes and returns. Only `send` needs adapting — the daemon sets the
/// inbound message handler on the real connection itself.
struct FireAndForgetConnection: DBusServerConnection {
    let connection: DBusClient.Connection

    init(_ connection: DBusClient.Connection) { self.connection = connection }

    func send(_ request: DBusRequest) async throws -> DBusMessage? {
        let sender: DBusClient.Send = await connection.send
        _ = try await sender.send(request)
        return nil
    }

    func setMessageHandler(_ handler: @escaping @Sendable (DBusMessage) async -> Void) async {
        await connection.setMessageHandler(handler)
    }
}

public enum TopDrawerServiceError: Error, CustomStringConvertible {
    case busNameUnavailable(name: String, replyCode: UInt32?)

    public var description: String {
        switch self {
        case .busNameUnavailable(let name, let code):
            return "Could not claim the D-Bus name \(name) "
                + "(RequestName reply \(code.map(String.init) ?? "nil")); "
                + "is another topdrawerd already running?"
        }
    }
}
#endif
