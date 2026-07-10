import Foundation

/// Pure transforms for the iOS-folder-like drawer groups: forming a group by
/// dropping one item onto another, popping an item back out, dissolving a group that
/// shrinks below two items, and renaming. All operate on a tab's top-level
/// `[DrawerItem]` and return a new array, so they're trivially unit-testable. Slot
/// normalization (top level and each group's sub-grid) is handled by
/// `assigningMissingSlots()`.
enum DrawerGrouping {
    /// The name a freshly-formed group gets until the user renames it.
    static let defaultName = "Group"
    /// A group with fewer children than this collapses back into loose items.
    static let dissolveThreshold = 2
    /// The item kinds that may go into a group — launchable targets only. Containers
    /// with their own dedicated slot (Trash, disks, cloud roots) never group.
    static let groupableKinds: Set<ItemKind> = [.application, .file, .folder, .url]

    /// Whether `item` can be dragged into (or used to seed) a group — a launchable
    /// target. A `.group` is never groupable as a *dragged* item (groups don't nest);
    /// as a drop *target* the caller allows `.group` explicitly (to append into it).
    static func isGroupable(_ item: DrawerItem) -> Bool { groupableKinds.contains(item.kind) }

    /// Groups `draggedID` onto `targetID` at the top level. If the target is already a
    /// group the dragged item joins it; otherwise both are wrapped in a new group at
    /// the target's slot. Returns the new top-level array, or `nil` when the move
    /// isn't groupable (onto itself, or dragging a group — groups don't nest) so the
    /// caller can fall back to a plain reorder.
    static func grouped(_ items: [DrawerItem], draggedID: UUID, ontoTargetID targetID: UUID) -> [DrawerItem]? {
        guard draggedID != targetID,
              let dragged = items.first(where: { $0.id == draggedID }),
              let target = items.first(where: { $0.id == targetID }),
              isGroupable(dragged),                                   // a launchable, non-group source
              target.kind == .group || isGroupable(target)           // onto a group (append) or another launchable
        else { return nil }

        var result = items.filter { $0.id != draggedID }
        guard let targetIndex = result.firstIndex(where: { $0.id == targetID }) else { return nil }
        if result[targetIndex].kind == .group {
            var child = dragged
            child.slot = -1
            result[targetIndex].children.append(child)
        } else {
            var first = target
            first.slot = 0
            var second = dragged
            second.slot = 1
            result[targetIndex] = DrawerItem(kind: .group, displayName: defaultName,
                                             slot: target.slot, children: [first, second])
        }
        return result.assigningMissingSlots()
    }

    /// Pops `childID` out of group `groupID` back to the top level, then dissolves any
    /// group left with fewer than `dissolveThreshold` children. Returns the top-level
    /// array unchanged if the child or group isn't found.
    static func removingFromGroup(_ items: [DrawerItem], childID: UUID, groupID: UUID) -> [DrawerItem] {
        guard let groupIndex = items.firstIndex(where: { $0.id == groupID && $0.kind == .group }),
              let child = items[groupIndex].children.first(where: { $0.id == childID }) else { return items }
        var result = items
        result[groupIndex].children.removeAll { $0.id == childID }
        var popped = child
        popped.slot = -1
        result.append(popped)
        return dissolvingSmallGroups(result).assigningMissingSlots()
    }

    /// Permanently removes an item at the top level or one level inside a group.
    /// Deleting a child also dissolves its group when fewer than two children remain.
    static func removingItem(_ items: [DrawerItem], id itemID: UUID) -> [DrawerItem] {
        var result = items
        if let index = result.firstIndex(where: { $0.id == itemID }) {
            result.remove(at: index)
            return result
        }
        guard let groupIndex = result.firstIndex(where: {
            $0.kind == .group && $0.children.contains(where: { $0.id == itemID })
        }) else { return items }
        result[groupIndex].children.removeAll { $0.id == itemID }
        return dissolvingSmallGroups(result)
    }

    /// Replaces an item at the top level or one level inside a group.
    static func updatingItem(_ items: [DrawerItem], with item: DrawerItem) -> [DrawerItem] {
        var result = items
        if let index = result.firstIndex(where: { $0.id == item.id }) {
            result[index] = item
            return result
        }
        guard let groupIndex = result.firstIndex(where: {
            $0.kind == .group && $0.children.contains(where: { $0.id == item.id })
        }),
              let childIndex = result[groupIndex].children.firstIndex(where: { $0.id == item.id }) else {
            return items
        }
        result[groupIndex].children[childIndex] = item
        return result
    }

    /// Replaces any group with fewer than `dissolveThreshold` children by its lone
    /// remaining child (taking the group's slot), and drops an empty group entirely.
    static func dissolvingSmallGroups(_ items: [DrawerItem]) -> [DrawerItem] {
        items.flatMap { item -> [DrawerItem] in
            guard item.kind == .group, item.children.count < dissolveThreshold else { return [item] }
            guard var only = item.children.first else { return [] }
            only.slot = item.slot
            return [only]
        }
    }

    /// Renames group `groupID` (a no-op if it isn't a group or isn't found).
    static func renaming(_ items: [DrawerItem], groupID: UUID, to name: String) -> [DrawerItem] {
        var result = items
        if let index = result.firstIndex(where: { $0.id == groupID && $0.kind == .group }) {
            result[index].displayName = name
        }
        return result
    }
}
