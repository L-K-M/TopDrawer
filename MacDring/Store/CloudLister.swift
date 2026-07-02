import Foundation

/// Lists the user's **cloud-storage drives** for a `.cloud` tab as transient
/// `DrawerItem`s (never stored in the document — re-read live each time the drawer
/// opens, like `FolderLister`).
///
/// Two sources: **iCloud Drive** (`~/Library/Mobile Documents/com~apple~CloudDocs`)
/// and the File-Provider providers macOS keeps under `~/Library/CloudStorage`
/// (Dropbox, Google Drive, OneDrive, Box, …). Each is a folder, not a volume, so it
/// is listed as a `.cloud` item: click to open in Finder (it can't be ejected). The
/// `.cloud` kind also lets `ItemView` give it a cloud-flavored default icon.
enum CloudLister {
    /// Cap so an unusual machine with many providers can't blow up the drawer.
    static let limit = 100

    /// A cloud-storage root (iCloud Drive or a `~/Library/CloudStorage` provider).
    struct CloudRoot: Equatable {
        let url: URL
        let name: String
    }

    /// The tab's cloud drives as launchable items (empty if not a cloud tab or none
    /// are available).
    static func contents(of tab: Tab) -> [DrawerItem] {
        guard tab.kind == .cloud else { return [] }
        return items(from: cloudRoots())
    }

    /// Pure: sorts the cloud roots by name and maps them to `.cloud` items with
    /// sequential grid slots, giving each a recognized provider a branded icon.
    static func items(from roots: [CloudRoot]) -> [DrawerItem] {
        let sorted = roots.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return sorted.prefix(limit).enumerated().map { index, root in
            // Stable (path-derived) id — same rationale as DisksLister.
            var item = DrawerItem(id: DrawerItem.stableID(kind: .cloud, url: root.url),
                                  kind: .cloud, displayName: root.name, url: root.url, slot: index)
            // A per-provider color/glyph "personality"; the tab's own `iconStyles`
            // override (applied after listing) still win for a user-customized icon.
            item.iconStyle = providerIconStyle(forName: root.name)
            return item
        }
    }

    /// A brand-flavored generated icon (color + glyph) for a recognized cloud
    /// provider, keyed loosely off its Finder display name; `nil` for an unknown
    /// provider, which keeps the generic cloud icon. Order matters — "Dropbox"
    /// before "Box", "OneDrive" before the generic "Drive". Pure / unit-tested.
    static func providerIconStyle(forName name: String) -> IconStyle? {
        let n = name.lowercased()
        func style(_ hex: String, _ symbol: String) -> IconStyle {
            IconStyle(base: .tile, colorHex: hex, symbol: symbol)
        }
        if n.contains("icloud") { return style("#3B9EFF", "icloud.fill") }
        if n.contains("dropbox") { return style("#0061FF", "shippingbox.fill") }
        if n.contains("onedrive") || n.contains("one drive") { return style("#0078D4", "cloud.fill") }
        if n.contains("google") || n.contains("drive") { return style("#1FA463", "triangle.fill") }
        if n.contains("box") { return style("#0061D5", "square.stack.3d.up.fill") }
        return nil
    }

    /// iCloud Drive plus the File-Provider cloud providers macOS keeps under
    /// `~/Library/CloudStorage` (Dropbox, Google Drive, OneDrive, Box, …). Reads only
    /// the user's own Library — no special permission — and degrades to an empty list
    /// if a directory can't be read. `home` is injectable for tests.
    static func cloudRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           fileManager: FileManager = .default) -> [CloudRoot] {
        var roots: [CloudRoot] = []

        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if fileManager.fileExists(atPath: iCloud.path) {
            roots.append(CloudRoot(url: iCloud, name: "iCloud Drive"))
        }

        let cloudStorage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        if let entries = try? fileManager.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) {
            for entry in entries {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                let display = fileManager.displayName(atPath: entry.path)
                roots.append(CloudRoot(url: entry, name: display.isEmpty ? entry.lastPathComponent : display))
            }
        }
        return roots
    }
}
