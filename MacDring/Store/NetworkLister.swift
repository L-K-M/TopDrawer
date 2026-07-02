import Foundation

/// Lists the user's **network shares** for a `.network` tab as transient
/// `DrawerItem`s (never stored in the document — re-read live each time the drawer
/// opens, like `DisksLister`).
///
/// Network shares are mounted *remote* volumes (SMB / AFP / NFS / WebDAV / …), kept
/// by the "browsable & **not local**" test so local disks, USB media, and mounted
/// disk images stay in the Disks tab. They're real volumes, so they're listed as
/// ejectable `.disk` items: click to open in Finder, **eject** (a Finder-style
/// "disconnect") from the item's menu. Cloud drives live in their own tab — see
/// `CloudLister`.
enum NetworkLister {
    /// Cap so an unusual machine with many mounts can't blow up the drawer.
    static let limit = 100

    /// A mounted volume's relevant properties, split out from `FileManager` so the
    /// filter/sort/map below is pure and unit-testable on its own.
    struct Volume: Equatable {
        let url: URL
        let name: String
        let isLocal: Bool
        let isBrowsable: Bool
    }

    /// The tab's mounted network shares as ejectable `.disk` items (empty if not a
    /// network tab or nothing remote is mounted).
    static func contents(of tab: Tab) -> [DrawerItem] {
        guard tab.kind == .network else { return [] }
        return items(from: mountedVolumes())
    }

    /// Pure: keeps the network (remote) volumes, sorts them by name, and maps them to
    /// `.disk` items with sequential grid slots.
    static func items(from volumes: [Volume]) -> [DrawerItem] {
        let shares = volumes.filter(isNetwork).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return shares.prefix(limit).enumerated().map { index, volume in
            // Stable (path-derived) id — same rationale as DisksLister.
            DrawerItem(id: DrawerItem.stableID(kind: .disk, url: volume.url),
                       kind: .disk, displayName: volume.name, url: volume.url, slot: index)
        }
    }

    /// A mounted volume is a "network share" when it's user-visible and **not local**
    /// — a remote SMB / AFP / NFS / WebDAV mount. Local disks, USB media, and mounted
    /// disk images report `isLocal == true`, so they're excluded (the Disks tab lists
    /// those).
    static func isNetwork(_ volume: Volume) -> Bool {
        volume.isBrowsable && !volume.isLocal
    }

    // MARK: FileManager bridge

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeIsLocalKey, .volumeIsBrowsableKey,
    ]

    private static func mountedVolumes() -> [Volume] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap(volume(at:))
    }

    private static func volume(at url: URL) -> Volume? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let name = values.volumeLocalizedName
            ?? values.volumeName
            ?? FileManager.default.displayName(atPath: url.path)
        return Volume(
            url: url,
            name: name,
            // A volume that doesn't report locality is assumed local, so it can't
            // masquerade as a network share; one that doesn't report browsability is
            // assumed visible (it came back from a `skipHiddenVolumes` enumeration).
            isLocal: values.volumeIsLocal ?? true,
            isBrowsable: values.volumeIsBrowsable ?? true
        )
    }
}
