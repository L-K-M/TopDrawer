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
    /// network tab or nothing remote is mounted). `listing` is the platform seam that
    /// vends mounted volumes — the macOS `FileManager` bridge by default, injectable
    /// for tests and a future Linux backend.
    static func contents(of tab: Tab, listing: VolumeListing = SystemVolumeListing()) -> [DrawerItem] {
        guard tab.kind == .network else { return [] }
        return items(from: listing.mountedVolumes().map {
            Volume(url: $0.url, name: $0.name, isLocal: $0.isLocal, isBrowsable: $0.isBrowsable)
        })
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
}
