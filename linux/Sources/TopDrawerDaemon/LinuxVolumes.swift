import Foundation
import MacDring

/// The kind of volume, matching the three ejectable/browsable docks the macOS app
/// splits mounted volumes into (`DisksLister` / `NetworkLister` / `CloudLister`). The
/// frontend buckets `GetVolumes` results by this into the Disks, Network, and Cloud
/// tabs.
public enum VolumeKind: String, Codable, Sendable {
    case disk       // removable / external local media
    case network    // a mounted remote share (SMB/NFS/sshfs/WebDAV/…)
    case cloud      // a cloud-storage provider (rclone/gvfs mount, or a Dropbox folder)
}

/// A source of the current volume snapshot: `ProcMounts` (Linux) in production, a fake
/// in tests. The daemon polls it to serve `GetVolumes` and to detect `VolumesChanged`.
public protocol VolumeSnapshotProviding: Sendable {
    func volumes() -> [LinuxVolume]
}

/// One user-facing volume as the daemon reports it over D-Bus. `id` is the mount point
/// (unique per mount, stable across a re-list) — `Eject` resolves it back to `device`
/// by re-reading the mount table, so the daemon holds no per-volume state.
public struct LinuxVolume: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let kind: VolumeKind
    /// The backing block device (`/dev/sda1`) for a removable disk; the mount source
    /// otherwise. Used by `Eject`; not part of the frontend's contract.
    public let device: String
    public let ejectable: Bool
}

/// A single line of `/proc/self/mountinfo`, reduced to the three fields classification
/// needs. Parsed rather than `/proc/self/mounts` because mountinfo is unambiguous
/// (fixed-position fields around the `-` separator) and carries the same device /
/// mount-point / fstype.
public struct RawMount: Equatable, Sendable {
    public let device: String
    public let mountPoint: String
    public let fsType: String
}

/// Parses `/proc/self/mountinfo`. Pure (takes the file's text) so it unit-tests against
/// fixtures on either platform.
public enum MountInfoParser {

    /// mountinfo escapes space, tab, newline and backslash in the mount point and mount
    /// source as octal `\NNN`. Reverse that so paths compare and display correctly.
    public static func unescape(_ field: String) -> String {
        guard field.contains("\\") else { return field }
        var result = ""
        var chars = Array(field.utf8)
        var i = 0
        while i < chars.count {
            if chars[i] == 0x5C, i + 3 < chars.count,          // backslash + 3 octal digits
               let d0 = octalDigit(chars[i + 1]),
               let d1 = octalDigit(chars[i + 2]),
               let d2 = octalDigit(chars[i + 3]) {
                result.unicodeScalars.append(UnicodeScalar(UInt8(d0 * 64 + d1 * 8 + d2)))
                i += 4
            } else {
                result.unicodeScalars.append(UnicodeScalar(chars[i]))
                i += 1
            }
        }
        return result
    }

    private static func octalDigit(_ byte: UInt8) -> Int? {
        (0x30...0x37).contains(byte) ? Int(byte - 0x30) : nil
    }

    /// Each mountinfo line: `id parent maj:min root mountpoint options [optfields…] - fstype source superopts`.
    /// The variable optional-field run is delimited by a standalone `-`; the three
    /// fields after it are fixed.
    public static func parse(_ mountinfo: String) -> [RawMount] {
        mountinfo.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 5,
                  let dash = fields.firstIndex(of: "-"),
                  dash + 2 < fields.count else { return nil }
            let mountPoint = unescape(fields[4])
            let fsType = fields[dash + 1]
            let source = unescape(fields[dash + 2])
            return RawMount(device: source, mountPoint: mountPoint, fsType: fsType)
        }
    }
}

/// Turns raw mounts (plus a few environment probes) into the classified, user-facing
/// volume list. Every input is injected so the whole thing is pure and fixture-tested;
/// `ProcMounts` (below, Linux-only) wires it to the real `/proc`, `/sys` and `$HOME`.
public enum VolumeClassifier {

    /// Pseudo / kernel filesystems that never represent a user volume.
    static let pseudoFSTypes: Set<String> = [
        "proc", "sysfs", "tmpfs", "devtmpfs", "devpts", "mqueue", "hugetlbfs", "cgroup",
        "cgroup2", "debugfs", "tracefs", "securityfs", "pstore", "bpf", "configfs",
        "fusectl", "autofs", "binfmt_misc", "rpc_pipefs", "nsfs", "ramfs", "efivarfs",
        "selinuxfs", "overlay", "squashfs", "fuse.portal", "fuse.gvfsd-fuse",
    ]

    /// Remote-share filesystems → the Network dock (mirrors `NetworkLister.isNetwork`:
    /// a browsable, non-local volume).
    static let networkFSTypes: Set<String> = [
        "cifs", "smb3", "smbfs", "nfs", "nfs4", "sshfs", "fuse.sshfs", "davfs",
        "fuse.davfs2", "afpfs", "ncpfs", "glusterfs", "ceph", "9p",
    ]

    /// Mount points we never surface even with a real fstype (system areas).
    static let systemPrefixes = ["/boot", "/proc", "/sys", "/dev", "/snap", "/var/lib/docker"]

    /// - Parameters:
    ///   - mounts: parsed `/proc/self/mountinfo`.
    ///   - user: `$USER`, for the `/media/$USER` + `/run/media/$USER` removable convention.
    ///   - isRemovable: whether a block device is removable (`/sys/block/<base>/removable`).
    ///   - dropboxRoots: cloud folders that aren't mounts (e.g. from `~/.dropbox/info.json`).
    public static func classify(mounts: [RawMount], user: String,
                                isRemovable: (String) -> Bool,
                                dropboxRoots: [String] = []) -> [LinuxVolume] {
        var volumes: [LinuxVolume] = []
        var seenPaths = Set<String>()

        for mount in mounts {
            guard !pseudoFSTypes.contains(mount.fsType),
                  !systemPrefixes.contains(where: { mount.mountPoint == $0 || mount.mountPoint.hasPrefix($0 + "/") }),
                  !seenPaths.contains(mount.mountPoint) else { continue }

            guard let volume = classifyOne(mount, user: user, isRemovable: isRemovable) else { continue }
            seenPaths.insert(volume.path)
            volumes.append(volume)
        }

        for root in dropboxRoots where !seenPaths.contains(root) {
            seenPaths.insert(root)
            volumes.append(LinuxVolume(id: root, name: displayName(forPath: root, fallback: "Dropbox"),
                                       path: root, kind: .cloud, device: root, ejectable: false))
        }

        return volumes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func classifyOne(_ mount: RawMount, user: String,
                                    isRemovable: (String) -> Bool) -> LinuxVolume? {
        let path = mount.mountPoint
        let name = displayName(forPath: path, fallback: mount.device)

        if networkFSTypes.contains(mount.fsType) {
            return LinuxVolume(id: path, name: name, path: path, kind: .network,
                               device: mount.device, ejectable: true)
        }
        // Cloud: rclone FUSE mounts (a real, separate mount), including remotes named
        // for a provider. gvfs/GOA providers (google-drive://, onedrive://) are NOT
        // separate mounts — they're virtual dirs inside the single fuse.gvfsd-fuse root,
        // so detecting them needs `gio mount -l`, a documented follow-up. Dropbox (a
        // plain synced folder, also not a mount) is picked up by the info.json probe.
        if mount.fsType == "fuse.rclone"
            || mount.device.hasPrefix("google-drive:") || mount.device.hasPrefix("onedrive:") {
            return LinuxVolume(id: path, name: name, path: path, kind: .cloud,
                               device: mount.device, ejectable: false)
        }
        // Disk: a real block device that is removable, or auto-mounted under the
        // /media/$USER (or /run/media/$USER) convention. Mirrors DisksLister.isEjectable
        // — external/removable media, not the internal system disk.
        let underMediaConvention = path.hasPrefix("/media/\(user)/") || path.hasPrefix("/run/media/\(user)/")
        if mount.device.hasPrefix("/dev/"), underMediaConvention || isRemovable(mount.device) {
            return LinuxVolume(id: path, name: name, path: path, kind: .disk,
                               device: mount.device, ejectable: true)
        }
        return nil
    }

    /// The volume's label: the mount point's last path component (what a user names a
    /// stick), falling back to the device basename for a root-level mount.
    static func displayName(forPath path: String, fallback: String) -> String {
        let last = (path as NSString).lastPathComponent
        if !last.isEmpty && last != "/" { return last }
        let deviceLast = (fallback as NSString).lastPathComponent
        return deviceLast.isEmpty ? fallback : deviceLast
    }
}

#if os(Linux)
/// The live Linux volume source: reads `/proc/self/mountinfo`, resolves removability
/// from `/sys/block`, probes `~/.dropbox/info.json`, and classifies. Also adapts to
/// `MacDring`'s `VolumeListing` (LP-12) so the seam has a real Linux backend.
public struct ProcMounts: VolumeSnapshotProviding {
    public init() {}

    /// The classified user-facing volumes right now.
    public func volumes() -> [LinuxVolume] {
        let mountinfo = (try? String(contentsOfFile: "/proc/self/mountinfo", encoding: .utf8)) ?? ""
        let user = ProcessInfo.processInfo.environment["USER"]
            ?? ProcessInfo.processInfo.environment["LOGNAME"] ?? ""
        return VolumeClassifier.classify(
            mounts: MountInfoParser.parse(mountinfo),
            user: user,
            isRemovable: Self.isRemovable(device:),
            dropboxRoots: dropboxRoots())
    }

    /// `true` when `device`'s parent block device is removable per
    /// `/sys/block/<base>/removable`. `/dev/sda1` → `sda`; `/dev/nvme0n1p2` → `nvme0n1`;
    /// `/dev/mmcblk0p1` → `mmcblk0`.
    static func isRemovable(device: String) -> Bool {
        guard device.hasPrefix("/dev/") else { return false }
        let base = baseBlockName(String(device.dropFirst("/dev/".count)))
        let flag = (try? String(contentsOfFile: "/sys/block/\(base)/removable", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flag == "1"
    }

    /// Strips a partition suffix to the parent block device. `nvme`/`mmcblk`/`loop`
    /// devices delimit the partition with `p` (`nvme0n1p2`); `sd`/`vd`/`hd` append the
    /// number directly (`sda1`).
    static func baseBlockName(_ name: String) -> String {
        if name.hasPrefix("nvme") || name.hasPrefix("mmcblk") || name.hasPrefix("loop") {
            if let range = name.range(of: "p[0-9]+$", options: .regularExpression) {
                return String(name[..<range.lowerBound])
            }
            return name
        }
        // sd/vd/hd style: the partition number is appended directly (`sda1` → `sda`).
        return String(name.prefix(while: { !$0.isNumber }))
    }

    /// Cloud folders that aren't mounts. Dropbox documents `~/.dropbox/info.json`
    /// (`{"personal":{"path":"…"}}`); read each account's `path`.
    private func dropboxRoots() -> [String] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let info = home.appendingPathComponent(".dropbox/info.json")
        guard let data = try? Data(contentsOf: info),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return json.values.compactMap { ($0 as? [String: Any])?["path"] as? String }
            .filter { fileManager.fileExists(atPath: $0) }
    }
}

/// `MacDring.VolumeListing` (LP-12) backed by `/proc`. The daemon reports volumes from
/// the richer `LinuxVolume` records directly (they carry the device + kind it needs),
/// so this adapter exists to give the platform seam a real Linux conformer and to be
/// unit-tested against the same classifier.
public struct ProcMountsVolumeListing: VolumeListing {
    private let source: ProcMounts
    public init(source: ProcMounts = ProcMounts()) { self.source = source }

    public func mountedVolumes() -> [MountedVolume] {
        source.volumes().map { volume in
            MountedVolume(
                url: URL(fileURLWithPath: volume.path),
                name: volume.name,
                isEjectable: volume.ejectable,
                isRemovable: volume.kind == .disk,
                isInternal: false,               // only external/remote/cloud reach here
                isLocal: volume.kind == .disk,   // network/cloud are non-local (NetworkLister test)
                isBrowsable: true)
        }
    }
}

/// Ejects/disconnects a volume. A removable disk is powered off through `udisksctl`
/// (unmount, then spin down so it's safe to unplug), falling back to `gio mount -e`; a
/// network or cloud mount is simply unmounted with `gio mount -u` (there's no drive to
/// power off).
public enum VolumeEjector {
    @discardableResult
    public static func eject(_ volume: LinuxVolume) -> Bool {
        switch volume.kind {
        case .disk:
            // Unmount first; only power-off's success matters for "safe to remove", but
            // fall back to gio if udisksctl isn't present or refuses.
            _ = LinuxProcess.succeeds("udisksctl", ["unmount", "-b", volume.device])
            if LinuxProcess.succeeds("udisksctl", ["power-off", "-b", volume.device]) { return true }
            return LinuxProcess.succeeds("gio", ["mount", "-e", volume.path])
        case .network, .cloud:
            return LinuxProcess.succeeds("gio", ["mount", "-u", volume.path])
        }
    }
}
#endif
