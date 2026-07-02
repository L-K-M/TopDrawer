import Foundation

/// Lists the mounted, **ejectable** volumes for a `.disks` tab as transient
/// `DrawerItem`s (never stored in the document — re-read live each time the
/// drawer opens, like `FolderLister`).
///
/// "Ejectable" here means the volumes a user would want a quick-eject dock for:
/// external/removable media, mounted disk images, and network shares. The startup
/// disk and other internal system volumes are deliberately omitted — offering to
/// eject the boot disk would be clutter at best. (A Folder tab on `/` or
/// `/Volumes` covers the "browse every volume" case.)
enum DisksLister {
    /// Cap so an unusual machine with dozens of mounts can't blow up the drawer.
    static let limit = 100

    /// A mounted volume's relevant properties, split out from `FileManager` so the
    /// filter/sort/map below is pure and unit-testable on its own.
    struct Volume: Equatable {
        let url: URL
        let name: String
        let isEjectable: Bool
        let isRemovable: Bool
        let isInternal: Bool
        let isBrowsable: Bool
    }

    /// The tab's mounted ejectable volumes as launchable disk items (empty if not a
    /// disks tab or nothing ejectable is mounted).
    static func contents(of tab: Tab) -> [DrawerItem] {
        guard tab.kind == .disks else { return [] }
        return items(from: mountedVolumes())
    }

    /// Pure: keeps the ejectable volumes, sorts them by name, and maps them to
    /// `.disk` items with sequential grid slots.
    static func items(from volumes: [Volume]) -> [DrawerItem] {
        let ejectable = volumes.filter(isEjectable).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return ejectable.prefix(limit).enumerated().map { index, volume in
            // Stable (path-derived) id: a re-list on mount/unmount keeps the
            // surviving volumes' identity, so per-item UI state (the Eject All
            // spinners) and icon caches follow them. See DrawerItem.stableID.
            DrawerItem(id: DrawerItem.stableID(kind: .disk, url: volume.url),
                       kind: .disk, displayName: volume.name, url: volume.url, slot: index)
        }
    }

    /// A volume belongs in the Disks dock when it's something the user can eject: a
    /// user-visible volume that is explicitly ejectable/removable, or simply isn't an
    /// internal system volume (external drives, network shares, mounted disk images).
    static func isEjectable(_ volume: Volume) -> Bool {
        guard volume.isBrowsable else { return false }
        return volume.isEjectable || volume.isRemovable || !volume.isInternal
    }

    // MARK: FileManager bridge

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey,
        .volumeIsEjectableKey, .volumeIsRemovableKey,
        .volumeIsInternalKey, .volumeIsBrowsableKey,
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
            isEjectable: values.volumeIsEjectable ?? false,
            isRemovable: values.volumeIsRemovable ?? false,
            isInternal: values.volumeIsInternal ?? false,
            // A volume that doesn't report browsability is assumed visible (it came
            // back from a `skipHiddenVolumes` enumeration).
            isBrowsable: values.volumeIsBrowsable ?? true
        )
    }
}
