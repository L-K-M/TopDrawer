import Foundation
#if canImport(Combine)
import Combine
#endif

/// Owns the persisted `LauncherDocument` and is the single source of truth for
/// tabs and their items. Loads from / saves to JSON in Application Support,
/// atomically and debounced, keeping one `.bak` of the previous good file.
///
/// `document` is `@Published` so SwiftUI settings views update live; `onChange`
/// is a lightweight hook for the (non-SwiftUI) `TabController` to reconcile the
/// on-screen windows after any mutation.
final class TabStore: ObservableObject {

    @Published private(set) var document: LauncherDocument

    /// Called after every mutation (on the main thread).
    var onChange: (() -> Void)?

    /// Whether a document was loaded from disk (vs. a fresh first run). Used to
    /// decide whether to seed a starter tab.
    let loadedFromDisk: Bool

    private let storeURL: URL
    private let bakURL: URL
    private let fileManager: FileManager
    private var saveWorkItem: DispatchWorkItem?

    struct BookmarkRepair {
        let original: Data
        let replacement: Data
    }

    struct ItemBookmarkKey: Hashable {
        let tabID: UUID
        let itemID: UUID
    }

    struct BookmarkRepairs {
        var folders: [UUID: BookmarkRepair] = [:]
        var targets: [ItemBookmarkKey: BookmarkRepair] = [:]
        var icons: [ItemBookmarkKey: BookmarkRepair] = [:]

        var isEmpty: Bool { folders.isEmpty && targets.isEmpty && icons.isEmpty }
    }

    /// Lock intent for the explicit item-lock APIs — an enum so calls read
    /// `setItemLock(.locked, …)` rather than passing an ambiguous Bool.
    enum ItemLockState {
        case locked, unlocked
    }

    // MARK: Init

    /// - Parameters:
    ///   - storeURL: where the JSON lives; defaults to Application Support.
    ///   - fileManager: injectable for tests.
    init(storeURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let url = storeURL ?? TabStore.defaultStoreURL(fileManager: fileManager)
        self.storeURL = url
        self.bakURL = url.deletingPathExtension().appendingPathExtension("bak.json")

        // Ensure the containing directory exists so saves succeed even for an
        // injected custom path.
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let primaryData = try? Data(contentsOf: url)
        if let primaryData, let doc = TabStore.decode(primaryData) {
            self.document = TabStore.normalizingSlots(doc)
            self.loadedFromDisk = true
        } else {
            // A primary that *exists* but won't decode safely is quarantined (renamed
            // aside), never overwritten: it may be hand-recoverable (e.g. JSON
            // truncated by a crash), and leaving it in place would let the next
            // save destroy it — first by rotating it over the good `.bak`, then,
            // if the store started empty and got seeded, by replacing it with a
            // starter document.
            if primaryData != nil {
                TabStore.quarantine(url, fileManager: fileManager)
            }
            if let data = try? Data(contentsOf: bakURL),
               let doc = TabStore.decode(data) {
                // Primary file missing/corrupt — recover from the backup.
                self.document = TabStore.normalizingSlots(doc)
                self.loadedFromDisk = true
            } else {
                self.document = .empty
                self.loadedFromDisk = false
            }
        }
    }

    /// Moves a corrupt launcher file aside as `launcher.corrupt-<stamp>.json`
    /// so no save path can ever overwrite it. User data is never deleted here.
    private static func quarantine(_ url: URL, fileManager: FileManager) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("launcher.corrupt-\(formatter.string(from: Date())).json")
        do {
            try fileManager.moveItem(at: url, to: dest)
            NSLog("Top Drawer: corrupt launcher document preserved at \(dest.lastPathComponent)")
        } catch {
            NSLog("Top Drawer: couldn't quarantine corrupt launcher document: \(error.localizedDescription)")
        }
    }

    /// Normalizes item slots in every tab, assigning missing slots while bounded
    /// capacity remains (and migrating documents saved before items had slots).
    private static func normalizingSlots(_ document: LauncherDocument) -> LauncherDocument {
        var doc = document
        for i in doc.tabs.indices {
            doc.tabs[i].items = doc.tabs[i].items.assigningMissingSlots()
        }
        return doc
    }

    static func defaultStoreURL(fileManager: FileManager) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory,
                                         in: .userDomainMask,
                                         appropriateFor: nil,
                                         create: true))
            ?? fileManager.temporaryDirectory
        // Legacy directory name from before the app was renamed to Top Drawer —
        // changing it would orphan every existing user's saved layout.
        let dir = base.appendingPathComponent("MacDring", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("launcher.json")
    }

    private static func decode(_ data: Data) -> LauncherDocument? {
        do {
            let document = try JSONDecoder().decode(LauncherDocument.self, from: data)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawTabs = root["tabs"] as? [Any] else {
                NSLog("Top Drawer: launcher document is missing a tabs array")
                return nil
            }
            if !rawTabs.isEmpty, document.tabs.isEmpty {
                NSLog("Top Drawer: launcher document contained tabs but none could be decoded")
                return nil
            }
            return document
        } catch {
            NSLog("Top Drawer: couldn't decode launcher document: \(error)")
            return nil
        }
    }

    // MARK: Reads

    var tabs: [Tab] { document.tabs }

    func tab(id: UUID) -> Tab? { document.tabs.first { $0.id == id } }

    // MARK: Mutations

    func addTab(_ tab: Tab) {
        mutate {
            var tab = tab
            tab.items = tab.items.assigningMissingSlots()
            $0.tabs.append(tab)
        }
    }

    func removeTab(id: UUID) {
        mutate {
            guard let i = $0.tabs.firstIndex(where: { $0.id == id }),
                  // Removing the tab destroys every item it holds — locks included.
                  !$0.tabs[i].items.contains(where: { $0.containsLockedItems }) else { return }
            $0.tabs.remove(at: i)
        }
    }

    /// Mutates the current value of a tab in place. Reading the tab inside the
    /// store prevents a Settings edit from replacing unrelated changes made since
    /// the editor was shown. Items get any missing slots filled after the change.
    func updateTab(id tabID: UUID, _ change: (inout Tab) -> Void) {
        mutate {
            guard let i = $0.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            change(&$0.tabs[i])
            $0.tabs[i].items = $0.tabs[i].items.assigningMissingSlots()
        }
    }

    /// Replaces the entire tab list (e.g. after a reorder in Settings).
    func replaceTabs(_ tabs: [Tab]) {
        mutate {
            $0.tabs = tabs.map { tab in
                var tab = tab
                tab.items = tab.items.assigningMissingSlots()
                return tab
            }
        }
    }

    /// Applies a change to every tab's behavior in one mutation. A general-purpose
    /// bulk edit (no UI calls it today — the global hover/auto-hide toggles are now
    /// live defaults each tab follows or overrides; see `TabBehavior.resolved`).
    func updateAllBehaviors(_ transform: (inout TabBehavior) -> Void) {
        mutate {
            for i in $0.tabs.indices { transform(&$0.tabs[i].behavior) }
        }
    }

    /// Re-mints bookmarks that have gone stale (their target moved or was renamed) so
    /// they keep resolving instead of silently falling back to a now-wrong path.
    /// Sweeps **every** bookmark the document holds: each item's target bookmark, its
    /// custom-icon bookmark, and each folder tab's directory bookmark. Resolves and
    /// re-mints off the main thread, then writes the refreshed bookmarks back on it
    /// only when each value still matches the snapshot. This prevents a repair from
    /// overwriting a newer user choice made while it was in flight. The write does not
    /// notify `onChange` (the resolved URLs are unchanged, so nothing needs to
    /// reconcile). Safe to call once at launch; a no-op when nothing is stale.
    func remintStaleBookmarks() {
        let snapshot = document.tabs
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let repairs = Self.makeBookmarkRepairs(in: snapshot) { data in
                guard let resolved = BookmarkResolver.resolve(data), resolved.isStale,
                      let minted = BookmarkResolver.makeBookmark(for: resolved.url) else { return nil }
                return minted
            }
            guard !repairs.isEmpty else { return }
            DispatchQueue.main.async {
                self?.mutate(notifyChange: false) {
                    Self.applyBookmarkRepairs(repairs, to: &$0)
                }
            }
        }
    }

    static func makeBookmarkRepairs(in tabs: [Tab], remint: (Data) -> Data?) -> BookmarkRepairs {
        var repairs = BookmarkRepairs()

        func repair(_ original: Data?) -> BookmarkRepair? {
            guard let original, let replacement = remint(original) else { return nil }
            return BookmarkRepair(original: original, replacement: replacement)
        }

        func collect(_ item: DrawerItem, tabID: UUID) {
            let key = ItemBookmarkKey(tabID: tabID, itemID: item.id)
            if let repair = repair(item.bookmark) { repairs.targets[key] = repair }
            if let repair = repair(item.customIconBookmark) { repairs.icons[key] = repair }
        }

        for tab in tabs {
            if let repair = repair(tab.folderBookmark) { repairs.folders[tab.id] = repair }
            for item in tab.items {
                collect(item, tabID: tab.id)
                if item.kind == .group {
                    for child in item.children { collect(child, tabID: tab.id) }
                }
            }
        }
        return repairs
    }

    static func applyBookmarkRepairs(_ repairs: BookmarkRepairs, to document: inout LauncherDocument) {
        func apply(to item: inout DrawerItem, tabID: UUID) {
            let key = ItemBookmarkKey(tabID: tabID, itemID: item.id)
            if let repair = repairs.targets[key], item.bookmark == repair.original {
                item.bookmark = repair.replacement
            }
            if let repair = repairs.icons[key], item.customIconBookmark == repair.original {
                item.customIconBookmark = repair.replacement
            }
        }

        for tabIndex in document.tabs.indices {
            let tabID = document.tabs[tabIndex].id
            if let repair = repairs.folders[tabID],
               document.tabs[tabIndex].folderBookmark == repair.original {
                document.tabs[tabIndex].folderBookmark = repair.replacement
            }
            for itemIndex in document.tabs[tabIndex].items.indices {
                apply(to: &document.tabs[tabIndex].items[itemIndex], tabID: tabID)
                if document.tabs[tabIndex].items[itemIndex].kind == .group {
                    for childIndex in document.tabs[tabIndex].items[itemIndex].children.indices {
                        apply(to: &document.tabs[tabIndex].items[itemIndex].children[childIndex], tabID: tabID)
                    }
                }
            }
        }
    }

    // MARK: Import / export

    /// Encodes the current document as pretty-printed JSON and writes it atomically.
    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    /// Replaces all tabs from an exported document. Decodes leniently (the same
    /// forward/again-compatible path as a normal load) and normalizes slots.
    /// Returns `false` without changing anything if the data can't be decoded safely.
    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard let doc = TabStore.decode(data) else { return false }
        guard doc.version <= LauncherDocument.currentVersion else {
            NSLog("Top Drawer: imported layout is version \(doc.version), newer than this build's \(LauncherDocument.currentVersion) — refusing import so newer data isn't downgraded")
            return false
        }
        let normalized = TabStore.normalizingSlots(doc)
        mutate {
            // Adopt the imported document's version as well as its tabs: if the
            // on-disk document happened to come from a newer build, `saveNow`
            // (rightly) refuses to write while `version` stays newer — which would
            // leave the freshly imported layout silently unpersistable.
            $0.version = normalized.version
            $0.tabs = normalized.tabs
        }
        return true
    }

    /// Adds an item to a tab, skipping it if the tab already holds an item pointing
    /// at the same target — so dropping (or choosing) the same app/file/link twice
    /// doesn't create a duplicate. Items without a resolvable target are always added.
    /// Returns the id of the item now in the tab for that target — the **existing**
    /// one on a duplicate, or the newly-added one — so a drop can place the right item
    /// even when it dedups (`nil` only if the tab wasn't found).
    @discardableResult
    func addItem(_ item: DrawerItem, toTab tabID: UUID) -> UUID? {
        var resultID: UUID?
        mutate {
            guard let i = $0.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            if let target = BookmarkResolver.url(for: item)?.standardized,
               let existing = $0.tabs[i].items.flattenedLaunchable().first(where: { BookmarkResolver.url(for: $0)?.standardized == target }) {
                resultID = existing.id   // already present (top level or inside a group) — reuse it, don't duplicate
                return
            }
            var item = item
            // `lockNewItems` applies to new entries only — the dedup hit above has
            // already returned, leaving the existing item's lock state untouched.
            if $0.tabs[i].lockNewItems { item.isLocked = true }
            $0.tabs[i].items.append(item)
            $0.tabs[i].items = $0.tabs[i].items.assigningMissingSlots()   // fill the new item's slot
            resultID = item.id
        }
        return resultID
    }

    /// Adds an ordered drop in one mutation, reusing items with matching targets at
    /// either the top level or inside groups. Returns each actual existing/new id once,
    /// in first-seen drop order. When `start` is non-nil, top-level results are placed
    /// in an ordered run from that slot while preserving slots occupied by other items.
    @discardableResult
    func addItems(_ items: [DrawerItem], toTab tabID: UUID, startingAt start: Int? = nil) -> [UUID] {
        guard !items.isEmpty,
              let tabIndex = document.tabs.firstIndex(where: { $0.id == tabID }) else { return [] }

        var tab = document.tabs[tabIndex]
        var resultIDs: [UUID] = []
        var seenIDs = Set<UUID>()
        var addedItem = false
        var newIDs = Set<UUID>()

        for item in items {
            let resultID: UUID
            if let target = BookmarkResolver.url(for: item)?.standardized,
               let existing = tab.items.flattenedLaunchable().first(where: {
                   BookmarkResolver.url(for: $0)?.standardized == target
               }) {
                resultID = existing.id
            } else {
                var item = item
                // `lockNewItems` locks new entries only — a deduplicated existing
                // item keeps its own lock state.
                if tab.lockNewItems { item.isLocked = true }
                tab.items.append(item)
                resultID = item.id
                addedItem = true
                newIDs.insert(item.id)
            }
            if seenIDs.insert(resultID).inserted { resultIDs.append(resultID) }
        }

        if addedItem { tab.items = tab.items.assigningMissingSlots() }

        var changed = addedItem
        if let start {
            let topLevelIDs = Set(tab.items.map(\.id))
            let placingIDs = resultIDs.filter { id in
                guard topLevelIDs.contains(id) else { return false }
                // First placement isn't a move: a newly added entry may take its
                // requested slot even while locked. A deduplicated existing entry
                // is reused but never repositioned while it (or a child inside it)
                // is locked — its slot stays a blocked occupant for the run below.
                return newIDs.contains(id)
                    || !(tab.items.first { $0.id == id }?.containsLockedItems ?? true)
            }
            let moving = Set(placingIDs)
            var blocked = Set(tab.items.filter { !moving.contains($0.id) }.map(\.slot))
            let maximum = PersistedLayoutBounds.maximumSlotOrOrder
            var slot = min(max(0, start), maximum)
            var placements: [(index: Int, slot: Int)]? = []
            for id in placingIDs {
                while blocked.contains(slot) {
                    guard slot < maximum else { placements = nil; break }
                    slot += 1
                }
                guard placements != nil,
                      let itemIndex = tab.items.firstIndex(where: { $0.id == id }) else { break }
                placements?.append((itemIndex, slot))
                blocked.insert(slot)
            }
            if let placements {
                for placement in placements where tab.items[placement.index].slot != placement.slot {
                    tab.items[placement.index].slot = placement.slot
                    changed = true
                }
            }
        }

        guard changed else { return resultIDs }
        mutate { $0.tabs[tabIndex] = tab }
        return resultIDs
    }

    /// Places `ids` at consecutive free grid slots starting at `start` — skipping any
    /// slot held by an item *not* in `ids` — preserving their order. Used when several
    /// items are dropped onto a slot together so they land in a tidy run from the
    /// target instead of scattering. If the complete run cannot fit below the slot
    /// bound, no items move. See BACKLOG.md's legacy ID index (I4).
    func placeItems(_ ids: [UUID], startingAt start: Int, inTab tabID: UUID) {
        guard !ids.isEmpty else { return }
        mutate { document in
            guard let ti = document.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            // Locked entries never join a bulk move: they keep their slots and
            // stay occupied blockers for the run that does place.
            let itemIndices = ids.compactMap { id in
                document.tabs[ti].items.firstIndex(where: { $0.id == id })
            }.filter { !document.tabs[ti].items[$0].containsLockedItems }
            guard !itemIndices.isEmpty else { return }
            let moving = Set(itemIndices.map { document.tabs[ti].items[$0].id })
            var blocked = Set(document.tabs[ti].items.filter { !moving.contains($0.id) }.map(\.slot))
            var slot = min(max(0, start), PersistedLayoutBounds.maximumSlotOrOrder)
            var placements: [(index: Int, slot: Int)] = []
            for index in itemIndices {
                while blocked.contains(slot) {
                    guard slot < PersistedLayoutBounds.maximumSlotOrOrder else { return }
                    slot += 1   // next slot free of a non-moving item
                }
                placements.append((index, slot))
                blocked.insert(slot)
            }
            for placement in placements {
                document.tabs[ti].items[placement.index].slot = placement.slot
            }
        }
    }

    func removeItem(id itemID: UUID, fromTab tabID: UUID) {
        mutate {
            guard let i = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  !Self.editingLocked(itemID, in: $0.tabs[i].items) else { return }
            // Removing an unlocked group child can still be denied: if it drops
            // the group below the dissolve threshold, the surviving children are
            // ejected back to the top level — an indirect move while one is locked.
            if let group = $0.tabs[i].items.first(where: {
                $0.kind == .group && $0.children.contains(where: { $0.id == itemID })
            }), Self.dissolutionWouldMoveLockedItems(group, removing: itemID) { return }
            $0.tabs[i].items = DrawerGrouping.removingItem($0.tabs[i].items, id: itemID)
        }
    }

    func updateItem(_ item: DrawerItem, inTab tabID: UUID) {
        mutate {
            guard let i = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  !Self.editingLocked(item.id, in: $0.tabs[i].items) else { return }
            // Lock state changes only through setItemLock/setAllItemLocks: an item
            // update must never smuggle an unlock past them (or flip one on).
            let item = Self.restoringPersistedLocks(item, in: $0.tabs[i].items)
            $0.tabs[i].items = DrawerGrouping.updatingItem($0.tabs[i].items, with: item)
        }
    }

    /// Sets an image override on a persistent item and clears its generated style, so
    /// there is only one custom icon source. Passing `nil` clears both overrides.
    func setCustomIconBookmark(_ bookmark: Data?, forItem itemID: UUID, inTab tabID: UUID) {
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  !Self.editingLocked(itemID, in: $0.tabs[ti].items) else { return }
            Self.mutateItem(itemID, in: &$0.tabs[ti].items) {
                $0.customIconBookmark = bookmark
                $0.iconStyle = nil
            }
        }
    }

    /// Sets a generated override on a persistent item and always clears its image
    /// bookmark. A `nil` style is the generated editor's "Use Default" result.
    func setIconStyle(_ style: IconStyle?, forItem itemID: UUID, inTab tabID: UUID) {
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  !Self.editingLocked(itemID, in: $0.tabs[ti].items) else { return }
            Self.mutateItem(itemID, in: &$0.tabs[ti].items) {
                $0.iconStyle = style
                $0.customIconBookmark = nil
            }
        }
    }

    /// Applies an item mutation at the top level or one level inside a group. Groups
    /// cannot nest, and their children are persistent items too.
    private static func mutateItem(_ itemID: UUID, in items: inout [DrawerItem],
                                   _ change: (inout DrawerItem) -> Void) {
        if let i = items.firstIndex(where: { $0.id == itemID }) {
            change(&items[i])
            return
        }
        for i in items.indices where items[i].kind == .group {
            if let j = items[i].children.firstIndex(where: { $0.id == itemID }) {
                change(&items[i].children[j])
                return
            }
        }
    }

    /// Sets (or clears, with `nil`) the generated-icon override for a **live** item —
    /// one produced by a folder/disks/network/cloud listing — keyed by its path on
    /// the owning tab. Persistent `.items` carry their override on the item instead
    /// (via `updateItem`).
    func setIconStyle(_ style: IconStyle?, forItemPath path: String, inTab tabID: UUID) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].iconStyles[path] = style
            }
        }
    }

    /// Places an item at a grid `slot`. If another item already occupies that slot
    /// they swap (so the slot the dragged item left becomes the other's); if the
    /// slot is empty the item simply moves there, leaving a gap. This is what makes
    /// free arrangement with gaps possible.
    func placeItem(_ itemID: UUID, atSlot slot: Int, inTab tabID: UUID) {
        guard PersistedLayoutBounds.normalizedSlot(slot) == slot else { return }
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  let ii = $0.tabs[ti].items.firstIndex(where: { $0.id == itemID }),
                  // A locked item can't move — and a group holding a locked child
                  // can't either: moving the container would move the child.
                  !$0.tabs[ti].items[ii].containsLockedItems else { return }
            let oldSlot = $0.tabs[ti].items[ii].slot
            guard oldSlot != slot else { return }
            if let occupant = $0.tabs[ti].items.firstIndex(where: { $0.slot == slot }) {
                // The swap moves the occupant too — denied while it's protected.
                guard !$0.tabs[ti].items[occupant].containsLockedItems else { return }
                $0.tabs[ti].items[occupant].slot = oldSlot
            }
            $0.tabs[ti].items[ii].slot = slot
        }
    }

    // MARK: Groups (iOS-folder-like)

    /// Forms a group from `draggedID` dropped onto `targetID` (or drops the dragged
    /// item into `targetID` when it's already a group). A no-op if the move isn't
    /// groupable (see `DrawerGrouping.grouped`), so the caller can have fallen back to
    /// a plain reorder.
    func groupItems(draggedID: UUID, ontoTargetID targetID: UUID, inTab tabID: UUID) {
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                   let grouped = DrawerGrouping.grouped($0.tabs[ti].items,
                                                       draggedID: draggedID, ontoTargetID: targetID) else { return }
            $0.tabs[ti].items = grouped
        }
    }

    /// Pops `childID` out of group `groupID` back to the top level, dissolving the
    /// group if it drops below two items.
    func removeFromGroup(childID: UUID, groupID: UUID, inTab tabID: UUID) {
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  let group = $0.tabs[ti].items.first(where: { $0.id == groupID && $0.kind == .group }),
                  // A locked group protects every child edit; a locked child can't
                  // be popped (that moves it); and a pop that dissolves the group
                  // can't eject a locked survivor.
                  !group.isLocked,
                  let child = group.children.first(where: { $0.id == childID }),
                  !child.isLocked,
                  !Self.dissolutionWouldMoveLockedItems(group, removing: childID) else { return }
            $0.tabs[ti].items = DrawerGrouping.removingFromGroup($0.tabs[ti].items,
                                                                 childID: childID, groupID: groupID)
        }
    }

    /// Renames group `groupID` (the inline field in the open-group header).
    func renameGroup(groupID: UUID, to name: String, inTab tabID: UUID) {
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  let group = $0.tabs[ti].items.first(where: { $0.id == groupID && $0.kind == .group }),
                  !group.isLocked else { return }
            $0.tabs[ti].items = DrawerGrouping.renaming($0.tabs[ti].items, groupID: groupID, to: name)
        }
    }

    /// Reorders a child within its group's sub-grid, with the same swap-or-move-into-a-
    /// gap semantics as `placeItem` one level down.
    func placeItemInGroup(_ itemID: UUID, atSlot slot: Int, groupID: UUID, inTab tabID: UUID) {
        guard PersistedLayoutBounds.normalizedSlot(slot) == slot else { return }
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  let gi = $0.tabs[ti].items.firstIndex(where: { $0.id == groupID && $0.kind == .group }),
                  // The group's lock covers its children; a locked child can't move.
                  !$0.tabs[ti].items[gi].isLocked,
                  let ii = $0.tabs[ti].items[gi].children.firstIndex(where: { $0.id == itemID }),
                  !$0.tabs[ti].items[gi].children[ii].isLocked else { return }
            let oldSlot = $0.tabs[ti].items[gi].children[ii].slot
            guard oldSlot != slot else { return }
            if let occupant = $0.tabs[ti].items[gi].children.firstIndex(where: { $0.slot == slot }) {
                // The swap would move the occupant child too — denied while locked.
                guard !$0.tabs[ti].items[gi].children[occupant].isLocked else { return }
                $0.tabs[ti].items[gi].children[occupant].slot = oldSlot
            }
            $0.tabs[ti].items[gi].children[ii].slot = slot
        }
    }

    /// Updates just a tab's anchor (used during drag-to-reposition). Pass
    /// `notify: false` to persist the change without triggering `onChange` — used by
    /// the de-overlap layout pass, which runs *inside* a reconcile and writes the
    /// settled positions back so they stay legal, without provoking another reconcile.
    func setAnchor(_ anchor: ScreenAnchor, forTab tabID: UUID, notify: Bool = true) {
        mutate(notifyChange: notify) {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].anchor = anchor
            }
        }
    }

    func setLocked(_ locked: Bool, forTab tabID: UUID) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].locked = locked
            }
        }
    }

    /// Updates a notes tab's text (edited live in the drawer). Does **not** notify
    /// `onChange`, so editing notes doesn't reconcile/refresh the open drawer and
    /// fight the text editor's cursor.
    func setNotes(_ notes: String, forTab tabID: UUID) {
        mutate(notifyChange: false) {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].notes = notes
            }
        }
    }

    /// Persist on drag completion without reconciling the editor mid-interaction.
    func setNotesSize(_ size: NotesDrawerSize?, forTab tabID: UUID) {
        guard let tab = tab(id: tabID), tab.kind == .notes, tab.notesSize != size else { return }
        mutate(notifyChange: false) {
            guard let i = $0.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            $0.tabs[i].notesSize = size
        }
    }

    // MARK: Item locks

    /// Whether edits to `id` are currently locked out — the item's own lock, a
    /// locked owning group, or (for a group) a locked child whose container can't
    /// move or dissolve without disturbing it. Drives UI/controller editing checks.
    func isItemEditingLocked(_ id: UUID, inTab tabID: UUID) -> Bool {
        guard let tab = tab(id: tabID) else { return false }
        return Self.editingLocked(id, in: tab.items)
    }

    /// Explicitly locks or unlocks one item — the only per-item way lock state can
    /// change (`updateItem` preserves the persisted lock). Locking a group covers
    /// its children through `editingLocked` without rewriting their own flags, so
    /// unlocking the group later loses nothing. Unlocking a child *inside* a locked
    /// group is denied until the group is unlocked — the group's lock owns its
    /// children, so a lone child unlock would be a half-state. `setAllItemLocks`
    /// clears a group and its children together.
    func setItemLock(_ state: ItemLockState, forItem id: UUID, inTab tabID: UUID) {
        guard state == .locked
                || !Self.insideLockedGroup(id, in: tab(id: tabID)?.items ?? []) else { return }
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            Self.mutateItem(id, in: &$0.tabs[ti].items) { $0.isLocked = state == .locked }
        }
    }

    /// Explicitly locks or unlocks every item in the tab, groups and their children
    /// included — the one call that can clear a locked group and its children in a
    /// single pass.
    func setAllItemLocks(_ state: ItemLockState, inTab tabID: UUID) {
        let locked = state == .locked
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            for i in $0.tabs[ti].items.indices {
                $0.tabs[ti].items[i].isLocked = locked
                for j in $0.tabs[ti].items[i].children.indices {
                    $0.tabs[ti].items[i].children[j].isLocked = locked
                }
            }
        }
    }

    /// Whether a lock protects `itemID` from editing inside `items`: the item's own
    /// lock; a locked group's ownership when it's a child; or, for a top-level
    /// group, a locked child within — moving or deleting the container would move
    /// or destroy that child.
    private static func editingLocked(_ itemID: UUID, in items: [DrawerItem]) -> Bool {
        if let item = items.first(where: { $0.id == itemID }) {
            return item.containsLockedItems
        }
        for group in items where group.kind == .group {
            if let child = group.children.first(where: { $0.id == itemID }) {
                return group.isLocked || child.isLocked
            }
        }
        return false
    }

    /// Whether `itemID` sits inside a locked group.
    private static func insideLockedGroup(_ itemID: UUID, in items: [DrawerItem]) -> Bool {
        items.contains {
            $0.kind == .group && $0.isLocked && $0.children.contains(where: { $0.id == itemID })
        }
    }

    /// Whether removing `childID` from `group` drops it below the dissolve
    /// threshold while a locked child survives: dissolving ejects the survivors to
    /// the top level — an indirect move a lock must block.
    private static func dissolutionWouldMoveLockedItems(_ group: DrawerItem, removing childID: UUID) -> Bool {
        let survivors = group.children.filter { $0.id != childID }
        return survivors.count < DrawerGrouping.dissolveThreshold
            && survivors.contains(where: { $0.isLocked })
    }

    /// Finds an item at the top level or one level inside a group (groups don't
    /// nest).
    private static func item(_ itemID: UUID, in items: [DrawerItem]) -> DrawerItem? {
        if let item = items.first(where: { $0.id == itemID }) { return item }
        for group in items where group.kind == .group {
            if let child = group.children.first(where: { $0.id == itemID }) { return child }
        }
        return nil
    }

    /// Copies each persisted `isLocked` back onto an incoming item update (matching
    /// by id, one level into groups) so `updateItem` can't change a lock either way.
    private static func restoringPersistedLocks(_ item: DrawerItem, in items: [DrawerItem]) -> DrawerItem {
        var item = item
        if let persisted = Self.item(item.id, in: items) {
            item.isLocked = persisted.isLocked
        }
        item.children = item.children.map { Self.restoringPersistedLocks($0, in: items) }
        return item
    }

    // MARK: Persistence

    private func mutate(notifyChange: Bool = true, _ change: (inout LauncherDocument) -> Void) {
        var doc = document
        change(&doc)
        document = doc
        if notifyChange { onChange?() }
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Writes immediately (used on quit and in tests). Keeps a `.bak` copy of the
    /// previous file and writes atomically. The backup is rotated only **after**
    /// the new write succeeds — rotating first would destroy the previous good
    /// copy exactly when writes are failing (e.g. disk full), leaving the
    /// document nowhere but memory.
    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        // A document written by a newer Top Drawer (schema version above ours)
        // must never be rewritten by this build: our encoder would silently
        // drop everything it doesn't know about. The in-memory session still
        // works; only persistence is disabled.
        guard document.version <= LauncherDocument.currentVersion else {
            NSLog("Top Drawer: launcher document is version \(document.version), newer than this build's \(LauncherDocument.currentVersion) — not saving, so the newer document isn't damaged")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            let previous = fileManager.fileExists(atPath: storeURL.path)
                ? try? Data(contentsOf: storeURL)
                : nil
            try data.write(to: storeURL, options: .atomic)
            if let previous {
                try? previous.write(to: bakURL, options: .atomic)
            }
        } catch {
            NSLog("Top Drawer: failed to save launcher document: \(error.localizedDescription)")
        }
    }
}
