import Foundation

/// A filesystem snapshot, including its resolved drop target, read together off-main.
struct DrawerListing {
    let items: [DrawerItem]
    let truncated: Bool
    let folderURL: URL?

    static func read(_ tab: Tab) -> DrawerListing {
        let items: [DrawerItem]
        switch tab.kind {
        case .folder:
            let url = FolderLister.resolveFolder(tab)
            let listing = url.flatMap {
                try? FolderLister.listing(at: $0, sort: tab.folderSort, showsHidden: tab.folderShowsHidden)
            }
            return DrawerListing(items: listing?.items ?? [], truncated: listing?.truncated ?? false, folderURL: url)
        case .disks: items = DisksLister.contents(of: tab)
        case .network: items = NetworkLister.contents(of: tab)
        case .cloud: items = CloudLister.contents(of: tab)
        default: items = []
        }
        return DrawerListing(items: items, truncated: false, folderURL: nil)
    }
}
