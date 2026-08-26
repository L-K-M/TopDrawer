import Foundation

/// Lists **newly arrived** files — recently downloaded, copied, or saved — for a
/// `.fresh` tab, as transient `DrawerItem`s (never stored in the document; gathered
/// live each time the drawer opens, like the other listers). The data comes from
/// Spotlight via `SpotlightQuery` (ranked by `kMDItemDateAdded`) — joined, when the
/// opt-in direct scan is on (`Preferences.freshDirectScan`), by `FreshScanner`'s
/// filesystem read of the same zones; this is the pure part — turning those results
/// into ordered, slotted drawer items.
///
/// Named after the classic "Fresh"-style utilities that surface the file you just
/// grabbed so you don't have to go hunting for where it landed.
///
/// `public` only so the Linux daemon can read `scopes` (the Fresh landing zones); the
/// `items`/`merge` helpers stay module-internal.
public enum FreshLister {
    /// Cap so a busy Downloads folder can't blow up the drawer.
    static let limit = 40

    /// Newly-arrived files as launchable items, most-recently-added first, with
    /// sequential grid slots.
    static func items(from results: [RecentFileHit]) -> [DrawerItem] {
        let newestFirst = results.sorted { $0.date > $1.date }
        return newestFirst.prefix(limit).enumerated().map { index, result in
            // Transient items skip the per-file bookmark — never persisted, and every
            // read path falls back to `url`. See BACKLOG.md's legacy ID index (I1) / FolderLister.
            var item = DrawerItem.transientFileItem(result.url)
            item.slot = index
            item.date = result.date   // Date Added — shown by the list layout
            return item
        }
    }

    /// Combines a direct filesystem scan (`FreshScanner`) with a Spotlight lookup —
    /// either of which may be empty — into one most-recently-added-first list,
    /// de-duplicated by file URL. This is what lets an opted-in Fresh tab
    /// (`Preferences.freshDirectScan`) work with Spotlight **off** (the scan alone),
    /// **on** (both, the index reaching deeper sub-folders), or only partly indexed
    /// (their union); with the setting off — the prompt-free default (FB1 / PR #61) —
    /// the scan side is simply empty. When the same file appears in both, the newer
    /// date wins (they agree on Date Added, so this is just a tie-break).
    static func merge(_ scanned: [RecentFileHit], _ spotlight: [RecentFileHit]) -> [RecentFileHit] {
        var seen = Set<URL>()
        return (scanned + spotlight)
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.url.standardizedFileURL).inserted }
    }

    /// The directories a Fresh tab scans: the usual landing zones for new files.
    /// Reading them via Spotlight needs no special permission, and a missing folder
    /// simply contributes nothing. `home` is injectable for tests. `public` so the Linux
    /// daemon scans the same zones.
    public static func scopes(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["Downloads", "Desktop", "Documents"].map {
            home.appendingPathComponent($0, isDirectory: true)
        }
    }
}
