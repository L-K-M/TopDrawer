import Foundation

// The platform-neutral vocabulary of a "recent files" lookup, split out of
// `SpotlightQuery` (LP-08) so the listers that consume it — `RecentsLister`,
// `FreshLister`, `FreshScanner` — compile on Linux, where Spotlight
// (`NSMetadataQuery`) does not exist. macOS keeps `SpotlightQuery` as the querying
// implementation (behind `#if os(macOS)`), with `SpotlightQuery.Result` / `.Mode`
// preserved there as typealiases so existing macOS call sites are unchanged.

/// A single indexed or scanned file: where it lives, its display name, and the
/// ranking date (last-used or date-added, per the query mode).
struct RecentFileHit: Equatable {
    let url: URL
    let name: String
    let date: Date
}

/// What a recents/fresh lookup ranks by: most-recently **used** (Recents) or
/// most-recently **added** (Fresh — downloaded / copied / saved into its folder).
enum RecentQueryMode {
    case lastUsed
    case dateAdded

    /// The Spotlight metadata attribute this mode sorts and filters on. Only the macOS
    /// `SpotlightQuery` reads it; it's inert on Linux, which scans the filesystem
    /// directly (`FreshScanner`).
    var attribute: String {
        switch self {
        case .lastUsed: return "kMDItemLastUsedDate"
        case .dateAdded: return "kMDItemDateAdded"
        }
    }

    /// How far back to look. "Recent" is the whole point, so a window keeps the query
    /// light and the result meaningful (no need to gather the entire index).
    var window: TimeInterval {
        switch self {
        case .lastUsed: return 90 * 24 * 60 * 60
        case .dateAdded: return 30 * 24 * 60 * 60
        }
    }
}

/// A one-shot asynchronous "recent files" lookup. `SpotlightQuery` is the macOS
/// implementation (Spotlight); Linux has no system-index equivalent, so a Fresh tab
/// there relies on `FreshScanner`'s direct filesystem read instead. Behind a protocol
/// so a caller can hold the querying seam abstractly (and a Linux implementation can
/// land later without touching the consumers).
protocol RecentFilesQuerying {
    /// Whether a lookup is currently gathering (started, not yet finished or cancelled).
    var isGathering: Bool { get }
    /// Starts a fresh lookup, cancelling any in-flight one. `scopes` are the directory
    /// URLs to search under; `completion` fires once on the main queue with the newest
    /// `limit` hits (most-recent first), after which the lookup stops.
    func start(mode: RecentQueryMode, scopes: [URL], limit: Int,
               completion: @escaping ([RecentFileHit]) -> Void)
    /// Stops any in-flight lookup and forgets its completion (no callback will fire).
    func cancel()
}
