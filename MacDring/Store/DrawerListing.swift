import Foundation

/// A filesystem snapshot, including its resolved drop target, read together off-main.
struct DrawerListing {
    let items: [DrawerItem]
    let truncated: Bool
    let folderURL: URL?
    var errorMessage: String? = nil

    static func read(_ tab: Tab) -> DrawerListing {
        let items: [DrawerItem]
        switch tab.kind {
        case .folder:
            guard let url = FolderLister.resolveFolder(tab) else {
                let message = tab.folderBookmark == nil ? nil : "The saved folder could not be located."
                return DrawerListing(items: [], truncated: false, folderURL: nil, errorMessage: message)
            }
            do {
                let listing = try FolderLister.listing(at: url, sort: tab.folderSort, showsHidden: tab.folderShowsHidden)
                return DrawerListing(items: listing.items, truncated: listing.truncated, folderURL: url)
            } catch {
                return DrawerListing(items: [], truncated: false, folderURL: url,
                                     errorMessage: "Couldn’t read the folder. \(error.localizedDescription)")
            }
        case .disks: items = DisksLister.contents(of: tab)
        case .network: items = NetworkLister.contents(of: tab)
        case .cloud: items = CloudLister.contents(of: tab)
        default: items = []
        }
        return DrawerListing(items: items, truncated: false, folderURL: nil)
    }
}
