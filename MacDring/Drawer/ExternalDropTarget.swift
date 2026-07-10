import Foundation

/// A target reported by the currently displayed drawer content for external drops.
/// Occupied cells use stable item identity. A top-level slot is carried only when it
/// is unambiguous; empty cells also retain their local slot so their frames stay unique.
enum ExternalDropTarget: Hashable {
    case occupiedItem(id: UUID, topLevelPlacementSlot: Int?)
    case emptySlot(localSlot: Int, topLevelPlacementSlot: Int?)

    var topLevelPlacementSlot: Int? {
        switch self {
        case .occupiedItem(_, let slot), .emptySlot(_, let slot):
            return slot
        }
    }
}
