import Foundation
@testable import MacDring

/// A canned `VolumeListing` for tests: vends a fixed set of mounted volumes so the
/// Disks/Network listers' seam and their `MountedVolume` → `Volume` mapping can be
/// exercised end-to-end without a real `FileManager` volume enumeration.
struct FakeVolumeListing: VolumeListing {
    let volumes: [MountedVolume]
    func mountedVolumes() -> [MountedVolume] { volumes }
}

extension MountedVolume {
    /// A volume under `/Volumes/<name>` defaulted to a plain internal local disk — one the
    /// Disks tab excludes (not ejectable/removable, not external) and the Network tab
    /// excludes (local). Opt a fake *into* a dock by passing `ejectable:`/`removable:` (Disks)
    /// or `isLocal: false` (Network); `isInternal` defaults to `true` so a bare fake isn't
    /// kept by DisksLister's `!isInternal` branch by accident.
    static func fake(_ name: String, ejectable: Bool = false, removable: Bool = false,
                     isInternal: Bool = true, isLocal: Bool = true, browsable: Bool = true) -> MountedVolume {
        MountedVolume(url: URL(fileURLWithPath: "/Volumes/\(name)", isDirectory: true), name: name,
                      isEjectable: ejectable, isRemovable: removable, isInternal: isInternal,
                      isLocal: isLocal, isBrowsable: browsable)
    }
}
