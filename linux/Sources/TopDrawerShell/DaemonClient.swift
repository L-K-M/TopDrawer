#if os(Linux)
import DBUS
import Foundation

/// Client side of the `ch.lkmc.TopDrawer1` contract (LP-16): the tab strip and its
/// change notification. The constants mirror `TopDrawerService`'s deliberately — the
/// shell links no daemon code, only the wire contract, so a frontend can be built and
/// shipped against any daemon speaking it.
public enum DaemonClient {

    public static let busName = "ch.lkmc.TopDrawer"
    public static let objectPath = "/ch/lkmc/TopDrawer"
    public static let interfaceName = "ch.lkmc.TopDrawer1"

    /// Generous like the daemon's own 5 s calls: a loaded session bus can be slow.
    private static let callTimeoutNanoseconds: UInt64 = 5_000_000_000

    public enum ClientError: Error, Equatable {
        /// The daemon's well-known name lost its owner — it left the bus.
        /// `observeTabs` keeps retrying, so a UI can key its reconnecting placeholder
        /// on this case rather than a message string.
        case daemonLeftTheBus
        /// Both watch subscriptions ended — this connection itself is gone.
        case watchStreamsEnded
        /// The reply wasn't the `s` the contract promises (an error return or a peer
        /// answering the name that isn't topdrawerd).
        case badReply(String)
    }

    /// The `ERROR_NAME` header of an error reply, if any — the diagnostic a caller logs
    /// (e.g. `org.freedesktop.DBus.Error.ServiceUnknown` while the daemon starts).
    private static func errorName(of message: DBusMessage) -> String {
        guard case .string(let name)? = message.headerFields
            .first(where: { $0.code == .errorName })?.variant.value else { return "" }
        return name
    }

    /// One `GetDocument` call, returning the launcher JSON verbatim.
    public static func fetchDocument(_ connection: DBusClient.Connection) async throws -> String {
        let reply = try await connection.send(
            .createMethodCall(
                destination: busName, path: objectPath,
                interface: interfaceName, method: "GetDocument", body: []),
            timeoutNanoseconds: callTimeoutNanoseconds)

        guard let reply, reply.messageType == .methodReturn,
              let json = reply.body.first?.string else {
            throw ClientError.badReply(reply.map { "\($0.messageType) \(Self.errorName(of: $0))" } ?? "no reply")
        }
        return json
    }

    /// One fetch, parsed to tabs — the read a dock strip renders.
    public static func fetchTabs(_ connection: DBusClient.Connection) async throws -> [ShellTab] {
        ShellTab.parse(try await fetchDocument(connection))
    }

    /// The document watch: emits the current tab strip once, then re-fetches and
    /// re-emits on every `DocumentChanged` signal. On any failure (no daemon on the
    /// bus yet, daemon left the bus, timeout) reports via `onError`, waits
    /// `retryDelay`, and starts over — re-subscribing, because the signal
    /// subscription of a vanished daemon is dead. Never returns.
    public static func observeTabs(_ connection: DBusClient.Connection,
                                   onChange: @escaping @Sendable ([ShellTab]) -> Void,
                                   onError: @escaping @Sendable (Error) -> Void,
                                   retryDelay: Duration = .seconds(5)) async {
        while true {
            do {
                // Subscribe BEFORE the initial fetch: a DocumentChanged landing between
                // the fetch's reply and the match-rule installation would otherwise be
                // missed until the *next* change — a stale strip, unbounded on a
                // rarely-changing document. A signal racing the fetch now either arrives
                // (triggering a redundant, harmless re-fetch) or the change is already in
                // the fetched document; both converge. AddMatch needs no name owner, so
                // the no-daemon path still fails at the fetch and drives onError/retry.
                let changes = try await documentChanges(connection)
                let owners = try await ownerChanges(connection)
                onChange(try await fetchTabs(connection))
                for await event in watchEvents(changes, owners) {
                    switch event {
                    case .documentChanged:
                        onChange(try await fetchTabs(connection))
                    case .ownerGained:
                        // A (re)started daemon doesn't emit DocumentChanged at startup,
                        // so re-read whatever document it came back with.
                        onChange(try await fetchTabs(connection))
                    case .ownerLost:
                        // A vanished daemon emits nothing on this connection — without
                        // this watch the stream would sit silent and the strip would be
                        // stale forever. Report and fall into the retry cycle.
                        throw ClientError.daemonLeftTheBus
                    }
                }
                if Task.isCancelled { return }   // the streams end on cancel too
                // Ended without cancellation — our own connection is gone.
                onError(ClientError.watchStreamsEnded)
            } catch is CancellationError {
                return   // the caller shut the observer down; that's not a daemon problem
            } catch {
                onError(error)
            }
            do {
                try await Task.sleep(for: retryDelay)
            } catch {
                return
            }
        }
    }

    /// What the watch loop reacts to.
    private enum WatchEvent { case documentChanged, ownerGained, ownerLost }

    /// Merges the two subscriptions into one event stream. The supervisor task
    /// finishes the merged stream once both sources end (our own connection dying) —
    /// without it the consumer's for-await would hang forever and the retry loop
    /// would never see "watch streams ended".
    private static func watchEvents(_ changes: AsyncStream<DBusMessage>,
                                     _ owners: AsyncStream<DBusMessage>) -> AsyncStream<WatchEvent> {
        AsyncStream { continuation in
            let documents = Task {
                for await _ in changes { continuation.yield(.documentChanged) }
            }
            let ownership = Task {
                // NameOwnerChanged body: (name, old_owner, new_owner) — arg0-scoped to
                // our bus name by the match rule, so every event here is about the daemon.
                for await message in owners {
                    let newOwner = message.body.dropFirst(2).first?.string ?? ""
                    continuation.yield(newOwner.isEmpty ? .ownerLost : .ownerGained)
                }
            }
            Task {
                _ = await (documents.value, ownership.value)
                continuation.finish()   // no-op if we already threw or were cancelled
            }
            continuation.onTermination = { _ in
                documents.cancel()
                ownership.cancel()
            }
        }
    }

    /// The watch subscriptions' match rules, hoisted so the bus-side dedup in
    /// `addMatch` can add and remove exactly these strings. dbus-daemon keeps every
    /// AddMatch copy — one delivery per rule — so a retry cycle that re-adds without
    /// removing would multiply refetches per change.
    private static let documentChangedRule =
        "type='signal',sender='\(busName)',interface='\(interfaceName)',member='DocumentChanged'"
    private static let ownerChangedRule =
        "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',"
            + "member='NameOwnerChanged',arg0='\(busName)'"

    /// Installs `rule`, replacing any stale copy from an earlier retry cycle (the
    /// first RemoveMatch finds nothing — `try?` swallows that).
    private static func addMatch(_ connection: DBusClient.Connection, rule: String) async throws {
        _ = try? await connection.send(
            .createMethodCall(
                destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                interface: "org.freedesktop.DBus", method: "RemoveMatch",
                body: [.string(rule)]),
            timeoutNanoseconds: callTimeoutNanoseconds)

        let reply = try await connection.send(
            .createMethodCall(
                destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                interface: "org.freedesktop.DBus", method: "AddMatch",
                body: [.string(rule)]),
            timeoutNanoseconds: callTimeoutNanoseconds)
        guard let reply, reply.messageType == .methodReturn else {
            throw ClientError.badReply("AddMatch rejected: \(reply.map { Self.errorName(of: $0) } ?? "no reply")")
        }
    }

    /// Subscribes to `DocumentChanged` (the explicit match rule mirrors the daemon's
    /// tests: the subscription alone doesn't guarantee bus-side routing). Scoped to
    /// the daemon's well-known name — the bus resolves it to the current owner's
    /// unique name, so any local process spoofing the interface can't drive refetch
    /// churn, and restarts keep working.
    private static func documentChanges(_ connection: DBusClient.Connection) async throws -> AsyncStream<DBusMessage> {
        try await addMatch(connection, rule: documentChangedRule)
        return await connection.subscribeToSignal(interface: interfaceName, member: "DocumentChanged")
    }

    /// Subscribes to the bus's own `NameOwnerChanged` for the daemon's name, arg0-
    /// scoped by the match rule: the daemon leaving the bus is otherwise invisible on
    /// this connection (no signal, no error — just silence).
    private static func ownerChanges(_ connection: DBusClient.Connection) async throws -> AsyncStream<DBusMessage> {
        try await addMatch(connection, rule: ownerChangedRule)
        return await connection.subscribeToSignal(interface: "org.freedesktop.DBus", member: "NameOwnerChanged")
    }
}
#endif
