import Foundation

/// Direct-filesystem scan that ranks a directory's entries by the filesystem's own
/// **Date Added** (`addedToDirectoryDateKey` — the very attribute Finder shows as
/// "Date Added" and that Spotlight mirrors as `kMDItemDateAdded`).
///
/// **Opt-in only.** Listing `~/Downloads`, `~/Desktop`, or `~/Documents` directly
/// trips macOS's one-time folder-access (TCC) consent dialogs, so the default Fresh
/// pipeline is Spotlight-only — index reads never prompt (FB1 / PR #61). But
/// Spotlight isn't reliable on every Mac (off, still indexing, or excluding the
/// landing zones), so `Preferences.freshDirectScan` (Settings → General) adds this
/// scan back **in addition to** the Spotlight query: it seeds the drawer instantly
/// and backs the pill dot, and `FreshLister.merge` folds the two listings together.
/// The toggle owns the prompts explicitly — flipping it on fires them right there
/// (`promptForAccess`), never as a surprise at launch.
///
/// Shallow by design: it scans the **top level** of each scope (where downloads,
/// copies, and screenshots actually land), which keeps it synchronous and bounded.
/// Files saved deep inside sub-folders are left to Spotlight.
///
/// `public` so the Linux `topdrawerd` package can reuse this exact ranking with a
/// birth-time (`statx`) `dateAdded` closure — the plan's LP-18 hook. It returns
/// `RecentFileHit`s (also public); nothing else is pulled public.
public enum FreshScanner {
    /// How far back a file still counts as "fresh". Derived from `RecentQueryMode`'s
    /// `dateAdded` window — the single source of truth — so the direct scan and the
    /// Spotlight query can't drift on the cutoff.
    public static let window: TimeInterval = RecentQueryMode.dateAdded.window

    /// Newly-arrived files found by reading `scopes` directly, most-recently-added
    /// first and capped to `limit`. `now`, `fileManager`, and `dateAdded` are injectable
    /// so the filtering/ranking is unit-testable without depending on real Date-Added
    /// metadata.
    public static func results(scopes: [URL],
                        limit: Int,
                        now: Date = Date(),
                        fileManager: FileManager = .default,
                        dateAdded: (URL) -> Date? = FreshScanner.dateAdded(of:)) -> [RecentFileHit] {
        let cutoff = now.addingTimeInterval(-window)
        var seen = Set<URL>()
        var out: [RecentFileHit] = []
        for scope in scopes {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: scope,
                includingPropertiesForKeys: [.addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for url in urls {
                let standardized = url.standardizedFileURL
                guard seen.insert(standardized).inserted else { continue }
                guard let date = dateAdded(url), date >= cutoff else { continue }
                out.append(RecentFileHit(url: standardized, name: standardized.lastPathComponent, date: date))
            }
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Surfaces the landing zones' one-time folder-access (TCC) consent prompts —
    /// off the main thread, results discarded. Called when the direct-scan setting
    /// is switched **on**, so the dialogs appear immediately, in response to the
    /// very click that opted in — not at the next badge beat or drawer open, long
    /// after the user has moved on. Folders already granted (or denied) don't
    /// re-prompt; macOS remembers the answer per folder.
    static func promptForAccess(scopes: [URL] = FreshLister.scopes()) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = results(scopes: scopes, limit: 1)
        }
    }

    /// A file's "date added" to its folder, falling back to its creation then
    /// modification date when the volume doesn't carry the attribute — so every entry
    /// gets a sensible freshness date even on filesystems that don't track Date Added.
    /// (The Linux daemon injects its own `statx`-based closure instead of this default.)
    public static func dateAdded(of url: URL) -> Date? {
        let values = try? url.resourceValues(
            forKeys: [.addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate ?? values?.contentModificationDate
    }
}
