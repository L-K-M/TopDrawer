import Foundation

/// Where a `.recents` tab draws its history from. The classic source is MacDring's
/// own launch log (`RecentsStore`); `system` adds documents recently opened
/// *anywhere* — Finder, other apps — read live from the Spotlight index
/// (`kMDItemLastUsedDate`), which needs no special permission.
enum RecentsSource: String, Codable, CaseIterable, Identifiable, Equatable {
    /// Only targets opened from MacDring itself (the original behavior, and the default).
    case macDring
    /// Only documents recently opened anywhere on the Mac, via Spotlight.
    case system
    /// Both, merged most-recent-first and de-duplicated by location.
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .macDring: return "MacDring"
        case .system: return "System"
        case .both: return "Both"
        }
    }

    /// Whether this source includes MacDring's own launch history (read synchronously).
    var includesMacDring: Bool { self != .system }

    /// Whether this source includes the system-wide Spotlight recents (gathered async).
    var includesSystem: Bool { self != .macDring }
}
