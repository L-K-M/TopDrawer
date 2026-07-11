import Foundation
import Combine

/// The list of targets recently opened from Top Drawer — backs the `.recents` tab.
/// App-global launch history (like `Preferences`), persisted to `UserDefaults` as
/// JSON: most-recent-first, de-duplicated by URL, capped. `TabController` records a
/// launch here; `RecentsLister` reads it.
final class RecentsStore: ObservableObject {

    static let shared = RecentsStore()
    static let limit = 30

    @Published private(set) var items: [RecentItem]

    private let defaults: UserDefaults
    private static let key = "recentItems"

    /// A custom `UserDefaults` can be injected for tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = RecentsStore.load(from: defaults)
    }

    /// Records a freshly-opened target: moves it to the front, de-duplicating by URL,
    /// capped to `limit`.
    func record(_ item: RecentItem) {
        items = RecentsStore.merging(items, with: item, limit: RecentsStore.limit)
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Pure: prepend `newItem`, drop any older entry with the same URL, cap to `limit`.
    static func merging(_ existing: [RecentItem], with newItem: RecentItem, limit: Int) -> [RecentItem] {
        var result = existing.filter { $0.url != newItem.url }
        result.insert(newItem, at: 0)
        return Array(result.prefix(max(0, limit)))
    }

    /// Pure: orders a combined set of recents most-recent-first, drops older
    /// duplicates of the same URL, and caps to `limit`. Folds the system (Spotlight)
    /// recents into Top Drawer's own history for the `.both` source.
    static func deduplicatedByURL(_ items: [RecentItem], limit: Int) -> [RecentItem] {
        var seen = Set<URL>()
        let ordered = items.sorted { $0.date > $1.date }.filter { seen.insert($0.url).inserted }
        return Array(ordered.prefix(max(0, limit)))
    }

    // MARK: Persistence

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(items), forKey: RecentsStore.key)
        } catch {
            NSLog("Top Drawer: couldn't save recent items: \(error.localizedDescription)")
        }
    }

    private static func load(from defaults: UserDefaults) -> [RecentItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        // Decode each record failably: one unreadable element must not nil the whole
        // history — the next `record()` would persist the wipe. Mirrors the launcher
        // document's `FailableTab` / `FailableDrawerItem` lenient-decode policy.
        guard let wrapped = try? JSONDecoder().decode([FailableRecentItem].self, from: data) else { return [] }
        return wrapped.compactMap(\.item)
    }
}
