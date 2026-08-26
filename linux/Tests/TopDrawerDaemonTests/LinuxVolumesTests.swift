import XCTest
@testable import TopDrawerDaemon

/// Pure tests for the `/proc/self/mountinfo` parser and the volume classifier — the
/// LP-17 acceptance's "fixture mount tables". Cross-platform: no `/proc`, `/sys`, or
/// subprocess is touched (every input is injected), so these run on either CI.
final class LinuxVolumesTests: XCTestCase {

    // A representative mountinfo: pseudo filesystems, the internal root, a USB stick
    // (with an octal-escaped space in its label), a CIFS share, an sshfs mount, an
    // rclone cloud mount, and the gvfs FUSE root.
    private let mountinfo = """
    25 30 0:23 / /proc rw,nosuid,nodev,noexec shared:5 - proc proc rw
    26 30 0:24 / /sys rw,nosuid,nodev,noexec shared:6 - sysfs sysfs rw
    27 30 0:25 / /run/user/1000 rw,nosuid,nodev shared:7 - tmpfs tmpfs rw
    30 1 259:2 / / rw,relatime shared:1 - ext4 /dev/nvme0n1p2 rw
    31 30 259:1 / /boot/efi rw,relatime shared:2 - vfat /dev/nvme0n1p1 rw
    40 30 8:17 / /media/alice/My\\040Stick rw,nosuid,nodev shared:20 - vfat /dev/sdb1 rw
    41 30 0:50 / /home/alice/nas rw,relatime shared:21 - cifs //server/share rw
    42 30 0:51 / /home/alice/remote rw,nosuid,nodev shared:22 - fuse.sshfs alice@host:/ rw
    43 30 0:52 / /home/alice/cloud rw,nosuid,nodev shared:23 - fuse.rclone gdrive: rw
    44 30 0:60 / /run/user/1000/gvfs rw,nosuid,nodev shared:24 - fuse.gvfsd-fuse gvfsd-fuse rw
    """

    // MARK: - Parser

    func testParseExtractsDeviceMountPointAndFsType() {
        let mounts = MountInfoParser.parse(mountinfo)
        // The USB line: octal \040 decodes back to a space in the mount point.
        let stick = mounts.first { $0.device == "/dev/sdb1" }
        XCTAssertEqual(stick?.mountPoint, "/media/alice/My Stick")
        XCTAssertEqual(stick?.fsType, "vfat")

        let cifs = mounts.first { $0.fsType == "cifs" }
        XCTAssertEqual(cifs?.device, "//server/share")
        XCTAssertEqual(cifs?.mountPoint, "/home/alice/nas")
    }

    func testParseIgnoresMalformedLines() {
        XCTAssertTrue(MountInfoParser.parse("garbage with no dash separator here").isEmpty)
        XCTAssertTrue(MountInfoParser.parse("").isEmpty)
    }

    func testUnescapeHandlesOctalAndPassesPlainThrough() {
        XCTAssertEqual(MountInfoParser.unescape("/a\\040b\\011c"), "/a b\tc")
        XCTAssertEqual(MountInfoParser.unescape("/plain/path"), "/plain/path")
    }

    // MARK: - Classifier

    /// Nothing is removable and no dropbox folder exists — only the network and cloud
    /// mounts survive; the internal disk, /boot, and all pseudo filesystems are dropped.
    func testClassifyWithoutRemovablesKeepsOnlyNetworkAndCloud() {
        let volumes = VolumeClassifier.classify(
            mounts: MountInfoParser.parse(mountinfo), user: "alice",
            isRemovable: { _ in false })
        let byPath = Dictionary(uniqueKeysWithValues: volumes.map { ($0.path, $0) })

        XCTAssertNil(byPath["/"], "the internal root disk is not offered for eject")
        XCTAssertNil(byPath["/boot/efi"], "system mounts are excluded")
        XCTAssertNil(byPath["/proc"])
        XCTAssertNil(byPath["/run/user/1000/gvfs"], "the gvfs FUSE root is not a user volume")

        XCTAssertEqual(byPath["/home/alice/nas"]?.kind, .network)
        XCTAssertEqual(byPath["/home/alice/remote"]?.kind, .network)  // fuse.sshfs
        XCTAssertEqual(byPath["/home/alice/cloud"]?.kind, .cloud)     // fuse.rclone
        XCTAssertEqual(byPath["/home/alice/cloud"]?.ejectable, true,  // a cloud mount is disconnectable
                       "an rclone cloud mount is a real mount and can be disconnected")
    }

    /// The /media/$USER convention alone marks the stick as a removable disk, even when
    /// /sys/block reports non-removable.
    func testClassifyPicksUpDiskViaMediaConvention() {
        let volumes = VolumeClassifier.classify(
            mounts: MountInfoParser.parse(mountinfo), user: "alice",
            isRemovable: { _ in false })
        let stick = volumes.first { $0.path == "/media/alice/My Stick" }
        XCTAssertEqual(stick?.kind, .disk)
        XCTAssertEqual(stick?.name, "My Stick", "the label is the mount point's last component")
        XCTAssertEqual(stick?.device, "/dev/sdb1")
        XCTAssertTrue(stick?.ejectable ?? false)
    }

    /// A block device flagged removable in /sys is a disk even outside /media.
    func testClassifyPicksUpDiskViaSysRemovableFlag() {
        let line = "50 30 8:33 / /mnt/backup rw,relatime shared:30 - ext4 /dev/sdc1 rw"
        let volumes = VolumeClassifier.classify(
            mounts: MountInfoParser.parse(line), user: "alice",
            isRemovable: { $0 == "/dev/sdc1" })
        XCTAssertEqual(volumes.first?.kind, .disk)
        XCTAssertEqual(volumes.first?.path, "/mnt/backup")
    }

    /// A dropbox folder (not a mount) is added as a cloud volume and results are sorted.
    func testClassifyAddsDropboxRootsSortedByName() {
        let volumes = VolumeClassifier.classify(
            mounts: MountInfoParser.parse(mountinfo), user: "alice",
            isRemovable: { _ in false },
            dropboxRoots: ["/home/alice/Dropbox"])
        let dropbox = volumes.first { $0.path == "/home/alice/Dropbox" }
        XCTAssertEqual(dropbox?.kind, .cloud)
        XCTAssertEqual(dropbox?.name, "Dropbox")
        XCTAssertEqual(volumes.map(\.name), volumes.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    /// The /media convention is user-scoped: another user's media dir isn't offered as
    /// ejectable (that's exactly what the `user:` parameter distinguishes).
    func testClassifyIgnoresOtherUsersMediaDir() {
        let line = "60 30 8:18 / /media/bob/Stick rw shared:40 - vfat /dev/sdd1 rw"
        let volumes = VolumeClassifier.classify(
            mounts: MountInfoParser.parse(line), user: "alice",
            isRemovable: { _ in false })
        XCTAssertTrue(volumes.isEmpty, "another user's /media mount is not this user's to eject")
    }

    /// A cloud *mount* (rclone) is disconnectable, so it's ejectable; a Dropbox *folder*
    /// (not a mount) is not.
    func testCloudMountIsEjectableButDropboxFolderIsNot() {
        let line = "43 30 0:52 / /home/alice/cloud rw shared:23 - fuse.rclone gdrive: rw"
        let volumes = VolumeClassifier.classify(
            mounts: MountInfoParser.parse(line), user: "alice",
            isRemovable: { _ in false },
            dropboxRoots: ["/home/alice/Dropbox"])
        XCTAssertEqual(volumes.first { $0.path == "/home/alice/cloud" }?.ejectable, true)
        XCTAssertEqual(volumes.first { $0.path == "/home/alice/Dropbox" }?.ejectable, false)
    }

    func testBaseBlockNameStripsPartitionSuffix() {
        // Only reachable from Linux, where ProcMounts is compiled.
        #if os(Linux)
        XCTAssertEqual(ProcMounts.baseBlockName("sda1"), "sda")
        XCTAssertEqual(ProcMounts.baseBlockName("sda"), "sda")
        XCTAssertEqual(ProcMounts.baseBlockName("nvme0n1p2"), "nvme0n1")
        XCTAssertEqual(ProcMounts.baseBlockName("mmcblk0p1"), "mmcblk0")
        XCTAssertEqual(ProcMounts.baseBlockName("vdb"), "vdb")
        // A whole-disk loop device must survive intact (the trailing `p0`-style strip
        // must not fire): loop0 → loop0, but a partition loop0p1 → loop0.
        XCTAssertEqual(ProcMounts.baseBlockName("loop0"), "loop0")
        XCTAssertEqual(ProcMounts.baseBlockName("loop0p1"), "loop0")
        // device-mapper (LUKS/LVM) has no partition child.
        XCTAssertEqual(ProcMounts.baseBlockName("dm-0"), "dm-0")
        #endif
    }
}
