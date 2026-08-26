#if os(Linux)
import Foundation
import DBUS
import Logging

/// The Top Drawer daemon's D-Bus service (LP-16 skeleton).
///
/// Exports one object, `/ch/lkmc/TopDrawer`, implementing the `ch.lkmc.TopDrawer1`
/// interface on the **session** bus and claims the well-known name
/// `ch.lkmc.TopDrawer`:
/// - `Ping() -> s` — liveness probe (the LP-16 acceptance smoke test).
/// - `GetDocument() -> s` — the launcher JSON, served verbatim from disk.
/// - `Launch(s itemID) -> b` — stub; returns `false` (real launching is LP-19).
/// - `AddDroppedURIs(s tabID, as uris) -> b` — stub; returns `false` (drops are LP-17).
/// - signal `DocumentChanged()` — emitted when the launcher file changes on disk.
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
    public static let version = "0.1.0"

    private let source: LauncherDocumentSource
    private let logger: Logger
    private var connection: DBusClient.Connection?
    private var lastModified: Date?
    private var watchTask: Task<Void, Never>?

    public init(source: LauncherDocumentSource, logger: Logger = Logger(label: "topdrawerd")) {
        self.source = source
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
        interface.signals = [DBusObjectServer.Signal(name: "DocumentChanged")]
        await server.export(DBusObjectServer.ExportedObject(path: Self.objectPath,
                                                            interfaces: [interface]))

        // The server doesn't hook the connection itself — feed it every inbound call.
        await connection.setMessageHandler { message in
            await server.handle(message: message)
        }

        try await claimBusName(on: connection)

        lastModified = source.modificationDate()
        startWatching(interval: watchInterval)
    }

    /// Stops the file watcher (the D-Bus export goes away with the connection).
    public func stop() {
        watchTask?.cancel()
        watchTask = nil
    }

    // MARK: - Methods

    private func makeMethods() -> [DBusObjectServer.Method] {
        let source = self.source
        let logger = self.logger
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
                logger.info("AddDroppedURIs(\(tabID), \(uris.count) uris): not implemented in the LP-16 skeleton (lands in LP-17)")
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

    // MARK: - Document change watch

    private func startWatching(interval: Duration) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self?.checkForChange()
            }
        }
    }

    private func checkForChange() async {
        let current = source.modificationDate()
        guard current != lastModified else { return }
        lastModified = current
        await emitDocumentChanged()
    }

    /// Emits the `DocumentChanged` signal. Also callable directly (the tests use it
    /// to exercise the signal without waiting on the file-watch interval).
    public func emitDocumentChanged() async {
        guard let connection else { return }
        let signal = DBusRequest.createSignal(
            path: Self.objectPath, interface: Self.interfaceName, name: "DocumentChanged")
        // A signal expects no reply, so fire it through the `Send` actor rather than
        // `connection.send(_:)`, which would wait for a reply that never comes.
        let sender: DBusClient.Send = await connection.send
        do {
            _ = try await sender.send(signal)
        } catch {
            logger.debug("Couldn't emit DocumentChanged: \(error)")
        }
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
