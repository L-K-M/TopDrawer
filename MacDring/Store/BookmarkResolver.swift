import Foundation

/// Bridges file/app/folder URLs to and from the `Data` bookmarks stored in
/// `DrawerItem`. Bookmarks let an item keep working when its target is moved or
/// renamed.
///
/// The v1 app is **not sandboxed** (Developer ID distribution), so plain
/// bookmarks resolve without entitlements. For a future App Store (sandboxed)
/// build, switch to security-scoped bookmarks (`.withSecurityScope`) and wrap
/// access in `startAccessingSecurityScopedResource()` — see PLAN.md §10.
enum BookmarkResolver {

    struct Resolved: Equatable {
        let url: URL
        let isStale: Bool
    }

    /// Creates a bookmark for `url`, or `nil` if one can't be made.
    static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a bookmark back to a URL, reporting whether it went stale (the
    /// caller should re-create the bookmark from the resolved URL when so).
    static func resolve(_ data: Data) -> Resolved? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        return Resolved(url: url, isStale: stale)
    }

    /// The launchable URL for an item: the link for `.url` items, otherwise the
    /// resolved bookmark (falling back to any stored `url`).
    static func url(for item: DrawerItem) -> URL? {
        switch item.kind {
        case .url:
            return item.url
        default:
            if let data = item.bookmark, let resolved = resolve(data) {
                return resolved.url
            }
            return item.url
        }
    }

    /// Whether a file/app/folder item no longer points at anything on disk.
    /// `.url` items and `.group` containers are never considered broken here.
    static func isBroken(_ item: DrawerItem) -> Bool {
        guard item.kind != .url, item.kind != .group else { return false }
        guard let url = url(for: item) else { return true }
        return !FileManager.default.fileExists(atPath: url.path)
    }
}
