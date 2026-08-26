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
                onChange(try await fetchTabs(connection))
                for await _ in changes {
                    onChange(try await fetchTabs(connection))
                }
                if Task.isCancelled { return }   // the stream ends on cancel too
                // Stream ended without cancellation — the daemon's connection is gone.
                onError(ClientError.badReply("DocumentChanged stream ended"))
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

    /// Subscribes to `DocumentChanged` (the explicit `AddMatch` mirrors the daemon's
    /// tests: the subscription alone doesn't guarantee bus-side routing). Scoped to
    /// the daemon's well-known name — the bus resolves it to the current owner's
    /// unique name, so any local process spoofing the interface can't drive refetch
    /// churn, and restarts keep working.
    private static func documentChanges(_ connection: DBusClient.Connection) async throws -> AsyncStream<DBusMessage> {
        let reply = try await connection.send(
            .createMethodCall(
                destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                interface: "org.freedesktop.DBus", method: "AddMatch",
                body: [.string("type='signal',sender='\(busName)',interface='\(interfaceName)',member='DocumentChanged'")]),
            timeoutNanoseconds: callTimeoutNanoseconds)

        guard let reply, reply.messageType == .methodReturn else {
            throw ClientError.badReply("AddMatch rejected: \(reply.map { Self.errorName(of: $0) } ?? "no reply")")
        }
        return await connection.subscribeToSignal(interface: interfaceName, member: "DocumentChanged")
    }
}
#endif
