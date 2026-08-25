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
    /// A volume under `/Volumes/<name>` with every flag defaulted to a plain local disk.
    static func fake(_ name: String, ejectable: Bool = false, removable: Bool = false,
                     isInternal: Bool = false, isLocal: Bool = true, browsable: Bool = true) -> MountedVolume {
        MountedVolume(url: URL(fileURLWithPath: "/Volumes/\(name)", isDirectory: true), name: name,
                      isEjectable: ejectable, isRemovable: removable, isInternal: isInternal,
                      isLocal: isLocal, isBrowsable: browsable)
    }
}
