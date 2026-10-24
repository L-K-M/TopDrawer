import Foundation

/// Lists a folder tab's linked directory as transient `DrawerItem`s (not stored in
/// the document). Folders sort before files; the per-tab `folderSort` orders within
/// each group, and `folderShowsHidden` controls whether dotfiles are included. Capped
/// so a huge directory can't blow up the drawer.
enum FolderLister {
    static let limit = 300

    /// The directory a `.folder` tab points at, or `nil` if unset/unresolvable.
    static func resolveFolder(_ tab: Tab) -> URL? {
        if let data = tab.folderBookmark, let resolved = BookmarkResolver.resolve(data) {
            return resolved.url
        }
        return tab.folderURL
    }

    /// A directory entry's sort-relevant properties, read **once** per entry (so the
    /// comparator stays pure and doesn't re-stat on every comparison).
    struct Entry: Equatable {
        let url: URL
        let isDirectory: Bool
        let modified: Date
        var name: String { url.lastPathComponent }
        var ext: String { url.pathExtension.lowercased() }
    }

    /// The tab's directory contents as launchable items (empty if not a folder tab
    /// or the directory can't be read), ordered by the tab's `folderSort`.
    static func contents(of tab: Tab) -> [DrawerItem] {
        listing(of: tab).items
    }

    /// Like `contents(of:)`, but also reports whether the directory held more entries
    /// than `limit` (so the drawer can show a "300+" truncation badge) and why the
    /// listing is empty when the directory exists but can't be read. An unreadable
    /// directory must not masquerade as an empty one — the drawer shows the failure
    /// instead of a bare "This folder is empty".
    static func listing(of tab: Tab) -> (items: [DrawerItem], truncated: Bool, error: String?) {
        guard tab.kind == .folder, let url = resolveFolder(tab) else { return ([], false, nil) }
        do {
            let listing = try listing(at: url, sort: tab.folderSort, showsHidden: tab.folderShowsHidden)
            return (listing.items, listing.truncated, nil)
        } catch {
            NSLog("Top Drawer: couldn't list folder \(url.path): \(error.localizedDescription)")
            return ([], false, error.localizedDescription)
        }
    }

    /// Pop-up browsers use the same bounded listing but surface unreadable folders.
    static func listing(at url: URL, sort: FolderSort = .name,
                        showsHidden: Bool = false) throws -> (items: [DrawerItem], truncated: Bool) {
        let fileManager = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions = []
        if !showsHidden { options.insert(.skipsHiddenFiles) }
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        let urls = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)

        let entries = sorted(urls.map(entry(for:)), by: sort)
        let items = entries.prefix(limit).enumerated().map { index, entry -> DrawerItem in
            // Transient items skip the per-file bookmark — folder items are never
            // persisted and every read path falls back to `url`. See BACKLOG.md's legacy ID index (I1).
            var item = DrawerItem.transientFileItem(entry.url)
            item.slot = index
            item.date = entry.modified   // Date Modified — shown by the list layout
            return item
        }
        return (items, entries.count > limit)
    }

    /// Pure: folders before files, then the chosen order within each group.
    static func sorted(_ entries: [Entry], by sort: FolderSort) -> [Entry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }   // folders on top
            switch sort {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .dateModified:
                if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }   // newest first
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .kind:
                if lhs.ext != rhs.ext { return lhs.ext < rhs.ext }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private static func entry(for url: URL) -> Entry {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
        return Entry(
            url: url,
            isDirectory: values?.isDirectory ?? false,
            modified: values?.contentModificationDate ?? .distantPast
        )
    }
}
