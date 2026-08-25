import Foundation

/// Lists the recently-opened targets for a `.recents` tab as transient `DrawerItem`s
/// (never stored in the document — re-read live each time the drawer opens, like the
/// other listers). A tab's `recentsSource` decides what's included: Top Drawer's own
/// launch history (`RecentsStore`), the system-wide recents read from Spotlight, or
/// both merged. Click an item to re-open it.
///
/// This file holds the **synchronous** part — Top Drawer's history. The system source
/// is gathered asynchronously by `SpotlightQuery` (see `TabController`), then folded
/// in through `items(from:)` / `RecentsStore.deduplicatedByURL`.
enum RecentsLister {
    /// The synchronously-available items for the tab: Top Drawer's history when the
    /// source includes it, otherwise empty (the system part arrives async). Empty for
    /// a non-recents tab or when nothing has been opened yet.
    static func contents(of tab: Tab, store: RecentsStore = .shared) -> [DrawerItem] {
        guard tab.kind == .recents else { return [] }
        let history = tab.recentsSource.includesMacDring ? store.items : []
        return items(from: history)
    }

    /// Pure: maps recent records to launchable items, in order, with sequential slots.
    /// Ids are stable (target-derived), so a re-list after a launch or Spotlight merge
    /// preserves each row's identity. The list is de-duplicated by URL upstream, so
    /// stable ids stay unique within it.
    static func items(from recents: [RecentItem]) -> [DrawerItem] {
        recents.prefix(RecentsStore.limit).enumerated().map { index, recent in
            DrawerItem(id: DrawerItem.stableID(kind: recent.kind, url: recent.url),
                       kind: recent.kind, displayName: recent.name, url: recent.url,
                       slot: index, date: recent.date)   // last used — shown by the list layout
        }
    }
}

extension RecentItem {
    /// A recent record built from a system-index hit (the system recents source),
    /// detecting the kind/name from the file at that location.
    init(spotlight result: RecentFileHit) {
        let (kind, name) = DrawerItem.kindAndName(for: result.url)
        self.init(url: result.url, kind: kind, name: name, date: result.date)
    }
}
