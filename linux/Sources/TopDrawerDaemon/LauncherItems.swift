#if os(Linux)
import Foundation

/// A launchable item resolved out of the launcher document by its ID — the minimum the
/// daemon needs to act on `Launch(itemID)`, read straight from the raw JSON so the daemon
/// still needs no public `DrawerItem`/`ItemKind` type (the same raw-lookup approach as
/// `LauncherTabs` and `LauncherDocumentSource`).
public struct LauncherItem: Sendable, Equatable {
    public let id: String
    /// The `ItemKind` raw value: `application`, `file`, `folder`, `url`, `trash`, `disk`,
    /// `cloud`, `group`.
    public let kind: String
    public let name: String
    /// The item's target URL string as stored (a `file://` path or a web URL). On Linux the
    /// security-scoped `bookmark` is never present, so `url` is authoritative — matching the
    /// macOS `BookmarkResolver.url(for:)` fallback.
    public let url: String?

    /// The parsed target URL, if `url` is present and well-formed.
    public var targetURL: URL? { url.flatMap { URL(string: $0) } }
}

/// Finds an item by ID anywhere in the launcher document — across every tab's `items`,
/// descending into `group` items' `children` (matching `DrawerItem.flattenedLaunchable()`).
public enum LauncherItems {

    public static func find(id: String, in json: String) -> LauncherItem? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tabs = root["tabs"] as? [[String: Any]] else { return nil }
        for tab in tabs {
            if let items = tab["items"] as? [[String: Any]],
               let found = find(id: id, inItems: items) {
                return found
            }
        }
        return nil
    }

    private static func find(id: String, inItems items: [[String: Any]]) -> LauncherItem? {
        for item in items {
            if let itemID = item["id"] as? String, itemID == id {
                return LauncherItem(
                    id: id,
                    kind: item["kind"] as? String ?? "file",
                    name: item["displayName"] as? String ?? "",
                    url: item["url"] as? String)
            }
            if let children = item["children"] as? [[String: Any]],
               let found = find(id: id, inItems: children) {
                return found
            }
        }
        return nil
    }
}
#endif
