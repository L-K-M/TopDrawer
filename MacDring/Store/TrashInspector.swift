import Foundation
import Darwin

/// Decides whether the Trash is empty **the way Finder sees it** — across *every*
/// trash that `FileMover.emptyTrash` (Finder's "Empty Trash") would clear — without
/// listing any of them (the Trash is privacy-protected; a directory *listing* can
/// prompt, but reading directory *metadata* never does, so we stay permission-free).
///
/// This drives the Trash item's full/empty icon and whether "Empty Trash…" is
/// enabled, so both now match what Empty Trash would actually do. Replaces the old
/// home-`~/.Trash`-only, subdirectory-only check. See BACKLOG.md's legacy ID index (I5).
enum TrashInspector {

    /// Whether the whole Trash is empty: true only when every trash directory Finder
    /// would empty is empty. `fileManager` is injectable for tests.
    static func trashIsEmpty(fileManager: FileManager = .default) -> Bool {
        trashDirectories(fileManager: fileManager).allSatisfy { isEmpty($0, fileManager: fileManager) }
    }

    /// The total number of items across every trash Finder's "Empty Trash" clears —
    /// for the Trash item's count badge. Sums each directory's metadata entry count
    /// (no listing → no prompt). Like the full/empty icon it inherits the
    /// `.DS_Store`-counting caveat (BACKLOG.md R14, ex-B28).
    static func trashCount(fileManager: FileManager = .default) -> Int {
        trashDirectories(fileManager: fileManager).reduce(0) { $0 + (entryCount(of: $1) ?? 0) }
    }

    /// Every trash directory Finder's "Empty Trash" clears: the user's home Trash
    /// (boot volume) plus each *other* mounted volume's per-user `.Trashes/<uid>`
    /// that actually exists. (A volume only grows a `.Trashes/<uid>` once you trash
    /// something on it, so most contribute nothing.)
    static func trashDirectories(fileManager: FileManager = .default) -> [URL] {
        var directories: [URL] = []

        if let home = try? fileManager.url(for: .trashDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: false) {
            directories.append(home)
        } else {
            directories.append(fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash", isDirectory: true))
        }

        let uid = getuid()
        if let volumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                       options: [.skipHiddenVolumes]) {
            for volume in volumes {
                let perVolume = volume.appendingPathComponent(".Trashes/\(uid)", isDirectory: true)
                // The boot volume keeps the user's trash at ~/.Trash, so its
                // /.Trashes/<uid> won't exist and is skipped — no duplicate.
                if fileManager.fileExists(atPath: perVolume.path) { directories.append(perVolume) }
            }
        }
        return directories
    }

    /// Whether a single directory holds no entries, decided from directory metadata
    /// (no listing → no permission prompt).
    static func isEmpty(_ url: URL, fileManager: FileManager = .default) -> Bool {
        if let count = entryCount(of: url) { return count == 0 }
        // Fallback when the entry-count attribute is unavailable (rare; non-APFS/HFS+):
        // a directory's link count is 2 + its subdirectory count, so <= 2 means no
        // subfolders. Coarser (it can't see loose files) but never prompts.
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        if let linkCount = (attrs?[.referenceCount] as? NSNumber)?.intValue { return linkCount <= 2 }
        return false   // can't tell → treat as non-empty (a usable "Empty Trash" item)
    }

    /// The number of entries in a directory (files *and* subdirectories, excluding
    /// `.`/`..`), read via `getattrlist`'s `ATTR_DIR_ENTRYCOUNT`. This reads the
    /// directory's metadata, not its contents, so unlike `contentsOfDirectory` it
    /// counts loose files too and doesn't trip Trash access. `nil` if the filesystem
    /// doesn't supply the attribute (then the caller falls back).
    static func entryCount(of url: URL) -> Int? {
        url.withUnsafeFileSystemRepresentation { path -> Int? in
            guard let path else { return nil }
            var request = attrlist()
            request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
            request.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)

            // getattrlist packs the result as [u_int32 length][u_int32 entryCount].
            var buffer = AttrBuffer()
            let result = getattrlist(path, &request, &buffer, MemoryLayout<AttrBuffer>.stride, 0)
            // length < 8 means the attribute wasn't returned (unsupported).
            guard result == 0, buffer.length >= UInt32(MemoryLayout<AttrBuffer>.stride) else { return nil }
            return Int(buffer.entryCount)
        }
    }

    /// The fixed-layout result buffer for the single `ATTR_DIR_ENTRYCOUNT` request.
    private struct AttrBuffer { var length: UInt32 = 0; var entryCount: UInt32 = 0 }
}
