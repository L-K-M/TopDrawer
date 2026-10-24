import Foundation

/// Navigation follows occupied grid cells, not array indices or empty slots.
enum DrawerNavigation {
    enum Direction { case up, down, left, right }

    static func nextID(in items: [DrawerItem], current: UUID?, direction: Direction,
                       columns: Int, layout: DrawerLayout) -> UUID? {
        let ordered = layout == .list ? items : items.sorted { $0.slot < $1.slot }
        guard !ordered.isEmpty else { return nil }
        let forward = direction == .down || direction == .right
        guard let current, let index = ordered.firstIndex(where: { $0.id == current }) else {
            return forward ? ordered.first?.id : ordered.last?.id
        }
        if layout == .list {
            return ordered[min(max(index + (forward ? 1 : -1), 0), ordered.count - 1)].id
        }

        let columns = PersistedLayoutBounds.clampedGridColumns(columns)
        let selected = ordered[index]
        let row = selected.slot / columns
        let column = selected.slot % columns
        let candidates = ordered.filter { item in
            switch direction {
            case .left: return item.slot / columns == row && item.slot < selected.slot
            case .right: return item.slot / columns == row && item.slot > selected.slot
            case .up: return item.slot / columns < row
            case .down: return item.slot / columns > row
            }
        }
        return candidates.min { lhs, rhs in
            let leftRow = abs(lhs.slot / columns - row)
            let rightRow = abs(rhs.slot / columns - row)
            if leftRow != rightRow { return leftRow < rightRow }
            let leftColumn = abs(lhs.slot % columns - column)
            let rightColumn = abs(rhs.slot % columns - column)
            if leftColumn != rightColumn { return leftColumn < rightColumn }
            return lhs.slot < rhs.slot
        }?.id ?? selected.id
    }
}
