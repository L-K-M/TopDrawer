import AppKit

/// Opens a drawer item: launches/activates an app, opens a file or folder in its
/// default handler, or opens a URL. Uses `NSWorkspace`, so it needs no special
/// permission.
enum ItemLauncher {

    /// Launches the item. Returns `false` if it couldn't be resolved to anything
    /// openable (e.g. a broken bookmark).
    @discardableResult
    static func launch(_ item: DrawerItem) -> Bool {
        guard let url = BookmarkResolver.url(for: item) else { return false }

        switch item.kind {
        case .application:
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    NSLog("MacDring: failed to launch \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return true
        case .file, .folder, .url, .trash, .disk, .cloud:
            return NSWorkspace.shared.open(url)   // trash → Trash folder; disk → the volume; cloud → the folder, in Finder
        case .group:
            return false   // a group isn't launchable — clicking it opens the group; unreachable (it has no URL)
        }
    }

    /// Reveals a file or folder item in Finder.
    static func revealInFinder(_ item: DrawerItem) {
        guard item.kind != .url, let url = BookmarkResolver.url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens dropped `urls` with a specific application item (drop-onto-app).
    static func open(_ urls: [URL], withApp appItem: DrawerItem) {
        guard !urls.isEmpty, let appURL = BookmarkResolver.url(for: appItem) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("MacDring: open-with failed: \(error.localizedDescription)")
            }
        }
    }
}
