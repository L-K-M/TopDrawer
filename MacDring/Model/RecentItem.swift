import Foundation

/// A target recently opened from Top Drawer — the backing record for a `.recents` tab.
/// Tracked by Top Drawer itself (every drawer launch) rather than the system's recent
/// items, so it needs no special permission and no deprecated `LSSharedFileList`.
struct RecentItem: Codable, Equatable {
    /// The openable target (app/file/folder/cloud URL, or a web link).
    var url: URL
    var kind: ItemKind
    var name: String
    var date: Date

    init(url: URL, kind: ItemKind, name: String, date: Date) {
        self.url = url
        self.kind = kind
        self.name = name
        self.date = date
    }

    /// Decodes forward-compatibly, like `DrawerItem`: only the `url` — the part a
    /// record is useless without — may fail the element. A `kind` raw value written
    /// by a newer Top Drawer degrades to `.file` instead of throwing, which would
    /// otherwise take the whole history down with it (see `RecentsStore.load`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(URL.self, forKey: .url)
        kind = c.decodeLenient(ItemKind.self, forKey: .kind, fallback: .file)
        let decodedName = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        name = decodedName.isEmpty ? url.lastPathComponent : decodedName
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
    }

    private enum CodingKeys: String, CodingKey { case url, kind, name, date }
}

/// Decodes a single `RecentItem` without throwing: an unreadable element yields
/// `nil` (and is filtered out) rather than failing the whole `[RecentItem]` decode —
/// which would wipe the history, and the next save would persist the wipe. The same
/// pattern as `FailableTab` / `FailableDrawerItem`.
struct FailableRecentItem: Decodable {
    let item: RecentItem?

    init(from decoder: Decoder) throws {
        item = try? RecentItem(from: decoder)
    }
}
