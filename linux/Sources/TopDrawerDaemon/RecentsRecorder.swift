#if os(Linux)
import Foundation
import MacDring

/// Records launches into Top Drawer's own recents history and reads it back — the
/// **macDring** half of a `.recents` tab (the **system** half is `recently-used.xbel`,
/// LP-18). A `Sendable` seam so the actor's `@Sendable` D-Bus handlers can `await` it, and
/// so a fake can drive the tests deterministically.
public protocol RecentsRecording: Sendable {
    /// Record a freshly-launched target — most-recent-first, de-duplicated by URL, capped.
    func record(url: URL, kind: String, name: String, date: Date) async
    /// The recorded launch history as hits, newest first, capped to `limit`.
    func recents(limit: Int) async -> [RecentFileHit]
}

/// Production recorder backed by MacDring's portable `RecentsStore` (the same
/// `UserDefaults`-persisted history the macOS app records into). An `actor` so it's
/// `Sendable` despite wrapping the non-`Sendable` `ObservableObject` store, and so
/// concurrent launches serialize their writes.
public actor MacDringRecentsRecorder: RecentsRecording {
    private let store: RecentsStore

    public init(store: RecentsStore = .shared) { self.store = store }

    public func record(url: URL, kind: String, name: String, date: Date) {
        store.record(RecentItem(url: url,
                                kind: ItemKind(rawValue: kind) ?? .file,
                                name: name,
                                date: date))
    }

    public func recents(limit: Int) -> [RecentFileHit] {
        // RecentsStore keeps items most-recent-first, so a prefix is the newest `limit`.
        store.currentItems.prefix(max(0, limit)).map {
            RecentFileHit(url: $0.url, name: $0.name, date: $0.date)
        }
    }
}
#endif
