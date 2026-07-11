import Foundation

/// What a tab's drawer shows.
enum TabKind: String, Codable, CaseIterable, Identifiable {
    /// A freely-arranged grid/list of apps, files, folders, and links (the default).
    case items
    /// A free-text notes area.
    case notes
    /// A live listing of a chosen directory's contents.
    case folder
    /// A live listing of the mounted, ejectable volumes (each openable / ejectable).
    case disks
    /// A live listing of the user's mounted network shares (each openable / ejectable).
    case network
    /// A live listing of the user's cloud-storage drives (iCloud, Dropbox, …).
    case cloud
    /// A live listing of the targets recently opened from Top Drawer.
    case recents
    /// A live listing of files that recently arrived on the Mac (downloaded, copied,
    /// or saved) — the "Fresh" pile, ranked by date added.
    case fresh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .items: return "Items"
        case .notes: return "Notes"
        case .folder: return "Folder"
        case .disks: return "Disks"
        case .network: return "Network"
        case .cloud: return "Cloud"
        case .recents: return "Recents"
        case .fresh: return "Fresh"
        }
    }

    var defaultLayout: DrawerLayout {
        switch self {
        case .recents, .fresh:
            return .list
        case .items, .notes, .folder, .disks, .network, .cloud:
            return .grid
        }
    }
}
