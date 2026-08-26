import Foundation

/// A mounted volume's resource properties in a platform-neutral shape — the raw input the
/// Disks and Network listers filter into drawer items (`DisksLister.Volume` /
/// `NetworkLister.Volume` are the per-lister projections of this). Produced by a
/// `VolumeListing`. See PLAN.md §LP-12.
/// `public` so the Linux `topdrawerd` package (which depends on `MacDring` by path)
/// can implement `VolumeListing` from `/proc` and read these fields. All members are
/// standard-library types, so widening the access level pulls no other type public and
/// changes no macOS behavior.
public struct MountedVolume: Equatable {
    public let url: URL
    public let name: String
    public let isEjectable: Bool
    public let isRemovable: Bool
    public let isInternal: Bool
    public let isLocal: Bool
    public let isBrowsable: Bool

    public init(url: URL, name: String, isEjectable: Bool, isRemovable: Bool,
                isInternal: Bool, isLocal: Bool, isBrowsable: Bool) {
        self.url = url
        self.name = name
        self.isEjectable = isEjectable
        self.isRemovable = isRemovable
        self.isInternal = isInternal
        self.isLocal = isLocal
        self.isBrowsable = isBrowsable
    }
}

/// A source of the currently mounted volumes. macOS reads them from `FileManager`'s
/// volume enumeration (`SystemVolumeListing`); a platform without that concept vends
/// none, so the Disks/Network docks come up empty there. `public` so the Linux daemon
/// can provide its own `/proc`-backed conformer.
public protocol VolumeListing {
    func mountedVolumes() -> [MountedVolume]
}

/// The system volume source: macOS's `FileManager` volume enumeration read with the
/// resource keys the listers need. On a platform without mounted-volume metadata it
/// vends nothing. This is the single macOS FileManager bridge the Disks and Network
/// listers used to each carry privately.
struct SystemVolumeListing: VolumeListing {
    func mountedVolumes() -> [MountedVolume] {
        #if os(macOS)
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
            .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let name = values.volumeLocalizedName
                ?? values.volumeName
                ?? FileManager.default.displayName(atPath: url.path)
            return MountedVolume(
                url: url,
                name: name,
                isEjectable: values.volumeIsEjectable ?? false,
                isRemovable: values.volumeIsRemovable ?? false,
                isInternal: values.volumeIsInternal ?? false,
                // A volume that doesn't report locality is assumed local (so it can't
                // masquerade as a network share); one that doesn't report browsability is
                // assumed visible (it came back from a `skipHiddenVolumes` enumeration).
                isLocal: values.volumeIsLocal ?? true,
                isBrowsable: values.volumeIsBrowsable ?? true)
        }
        #else
        return []
        #endif
    }
}
