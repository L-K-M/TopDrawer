import AppKit

/// Unmounts and ejects a mounted volume — the Disks tab's eject action. Uses
/// `NSWorkspace`, which handles physical media, mounted disk images, and network
/// shares alike (the same call Finder's eject makes), so it needs no special
/// permission.
enum DiskEjector {

    /// Ejects a `.disk` item's volume. Returns `false` if it isn't a disk item, its
    /// volume can't be resolved, or the eject failed (e.g. a file is still in use).
    @discardableResult
    static func eject(_ item: DrawerItem) -> Bool {
        guard item.kind == .disk, let url = BookmarkResolver.url(for: item) else { return false }
        return eject(url)
    }

    @discardableResult
    static func eject(_ url: URL) -> Bool {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            return true
        } catch {
            NSLog("Top Drawer: couldn't eject \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }
}
