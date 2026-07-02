import Foundation

/// Direct-filesystem scan that ranks a directory's entries by the filesystem's own
/// **Date Added** (`addedToDirectoryDateKey` — the very attribute Finder shows as
/// "Date Added" and that Spotlight mirrors as `kMDItemDateAdded`).
///
/// **Not used by the live Fresh tab.** Listing `~/Downloads`, `~/Desktop`, or
/// `~/Documents` directly trips macOS's folder-access (TCC) consent dialogs —
/// breaking the app's no-permission promise (fable-is-awesome.md FB1) — so the Fresh
/// pipeline is Spotlight-only (index reads never prompt). This stays as tested pure
/// logic for a possible future *opt-in* "works without Spotlight" mode that would
/// own the prompt explicitly.
enum FreshScanner {
    /// How far back a file still counts as "fresh". Matches `SpotlightQuery.Mode`'s
    /// `dateAdded` window so the direct scan and the Spotlight query agree on the cutoff.
    static let window: TimeInterval = 30 * 24 * 60 * 60

    /// Newly-arrived files found by reading `scopes` directly, most-recently-added
    /// first and capped to `limit`. `now`, `fileManager`, and `dateAdded` are injectable
    /// so the filtering/ranking is unit-testable without depending on real Date-Added
    /// metadata.
    static func results(scopes: [URL],
                        limit: Int,
                        now: Date = Date(),
                        fileManager: FileManager = .default,
                        dateAdded: (URL) -> Date? = FreshScanner.dateAdded(of:)) -> [SpotlightQuery.Result] {
        let cutoff = now.addingTimeInterval(-window)
        var seen = Set<URL>()
        var out: [SpotlightQuery.Result] = []
        for scope in scopes {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: scope,
                includingPropertiesForKeys: [.addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for url in urls {
                let standardized = url.standardizedFileURL
                guard seen.insert(standardized).inserted else { continue }
                guard let date = dateAdded(url), date >= cutoff else { continue }
                out.append(SpotlightQuery.Result(url: standardized, name: standardized.lastPathComponent, date: date))
            }
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// A file's "date added" to its folder, falling back to its creation then
    /// modification date when the volume doesn't carry the attribute — so every entry
    /// gets a sensible freshness date even on filesystems that don't track Date Added.
    static func dateAdded(of url: URL) -> Date? {
        let values = try? url.resourceValues(
            forKeys: [.addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate ?? values?.contentModificationDate
    }
}
