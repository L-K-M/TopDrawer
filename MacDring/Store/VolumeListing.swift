import Foundation

/// A mounted volume's resource properties in a platform-neutral shape — the raw input the
/// Disks and Network listers filter into drawer items (`DisksLister.Volume` /
/// `NetworkLister.Volume` are the per-lister projections of this). Produced by a
/// `VolumeListing`. See PLAN.md §LP-12.
struct MountedVolume: Equatable {
    let url: URL
    let name: String
    let isEjectable: Bool
    let isRemovable: Bool
    let isInternal: Bool
    let isLocal: Bool
    let isBrowsable: Bool
}

/// A source of the currently mounted volumes. macOS reads them from `FileManager`'s
/// volume enumeration (`SystemVolumeListing`); a platform without that concept vends
/// none, so the Disks/Network docks come up empty there.
protocol VolumeListing {
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
