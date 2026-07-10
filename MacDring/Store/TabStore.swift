import Foundation
import Combine

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
            // A primary that *exists* but won't decode is quarantined (renamed
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

    /// Moves an undecodable launcher file aside as `launcher.corrupt-<stamp>.json`
    /// so no save path can ever overwrite it. User data is never deleted here.
    private static func quarantine(_ url: URL, fileManager: FileManager) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("launcher.corrupt-\(formatter.string(from: Date())).json")
        do {
            try fileManager.moveItem(at: url, to: dest)
            NSLog("MacDring: launcher document couldn't be decoded — preserved it at \(dest.lastPathComponent)")
        } catch {
            NSLog("MacDring: couldn't quarantine undecodable launcher document: \(error.localizedDescription)")
        }
    }

    /// Ensures every item in every tab has a valid, distinct grid slot (migrates
    /// older documents saved before items had slots).
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
        let dir = base.appendingPathComponent("MacDring", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("launcher.json")
    }

    private static func decode(_ data: Data) -> LauncherDocument? {
        do {
            return try JSONDecoder().decode(LauncherDocument.self, from: data)
        } catch {
            NSLog("MacDring: couldn't decode launcher document: \(error)")
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
        mutate { $0.tabs.removeAll { $0.id == id } }
    }

    /// Replaces a tab (matched by id) with an updated value. Items get any missing
    /// slots filled (the Settings editor appends items with an unassigned slot),
    /// matching `addItem` and the on-disk load so they render immediately — not
    /// only after a restart re-normalizes the document.
    func updateTab(_ tab: Tab) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tab.id }) {
                var tab = tab
                tab.items = tab.items.assigningMissingSlots()
                $0.tabs[i] = tab
            }
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
    /// without notifying `onChange` (the resolved URLs are unchanged, so nothing needs
    /// to reconcile). Safe to call once at launch; a no-op when nothing is stale.
    func remintStaleBookmarks() {
        let snapshot = document.tabs
        DispatchQueue.global(qos: .utility).async { [weak self] in
            func reminted(_ data: Data?) -> Data? {
                guard let data,
                      let resolved = BookmarkResolver.resolve(data), resolved.isStale,
                      let minted = BookmarkResolver.makeBookmark(for: resolved.url) else { return nil }
                return minted
            }
            var freshTargets: [UUID: Data] = [:]   // itemID → re-minted target bookmark
            var freshIcons: [UUID: Data] = [:]     // itemID → re-minted custom-icon bookmark
            var freshFolders: [UUID: Data] = [:]   // tabID → re-minted folder bookmark
            for tab in snapshot {
                if let minted = reminted(tab.folderBookmark) { freshFolders[tab.id] = minted }
                for item in tab.items {
                    if let minted = reminted(item.bookmark) { freshTargets[item.id] = minted }
                    if let minted = reminted(item.customIconBookmark) { freshIcons[item.id] = minted }
                }
            }
            guard !freshTargets.isEmpty || !freshIcons.isEmpty || !freshFolders.isEmpty else { return }
            DispatchQueue.main.async {
                self?.mutate(notifyChange: false) {
                    for ti in $0.tabs.indices {
                        if let minted = freshFolders[$0.tabs[ti].id] {
                            $0.tabs[ti].folderBookmark = minted
                        }
                        for ii in $0.tabs[ti].items.indices {
                            let id = $0.tabs[ti].items[ii].id
                            if let minted = freshTargets[id] { $0.tabs[ti].items[ii].bookmark = minted }
                            if let minted = freshIcons[id] { $0.tabs[ti].items[ii].customIconBookmark = minted }
                        }
                    }
                }
            }
        }
    }

    // MARK: Import / export

    /// The current document encoded as pretty-printed JSON, for backup/export.
    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(document)
    }

    /// Replaces all tabs from an exported document. Decodes leniently (the same
    /// forward/again-compatible path as a normal load) and normalizes slots.
    /// Returns `false` without changing anything if the data can't be decoded.
    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard let doc = TabStore.decode(data) else { return false }
        guard doc.version <= LauncherDocument.currentVersion else {
            NSLog("MacDring: imported layout is version \(doc.version), newer than this build's \(LauncherDocument.currentVersion) — refusing import so newer data isn't downgraded")
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

        for item in items {
            let resultID: UUID
            if let target = BookmarkResolver.url(for: item)?.standardized,
               let existing = tab.items.flattenedLaunchable().first(where: {
                   BookmarkResolver.url(for: $0)?.standardized == target
               }) {
                resultID = existing.id
            } else {
                tab.items.append(item)
                resultID = item.id
                addedItem = true
            }
            if seenIDs.insert(resultID).inserted { resultIDs.append(resultID) }
        }

        if addedItem { tab.items = tab.items.assigningMissingSlots() }

        var changed = addedItem
        if let start {
            let topLevelIDs = Set(tab.items.map(\.id))
            let placingIDs = resultIDs.filter { topLevelIDs.contains($0) }
            let moving = Set(placingIDs)
            var blocked = Set(tab.items.filter { !moving.contains($0.id) }.map(\.slot))
            var slot = max(0, start)
            for id in placingIDs {
                while blocked.contains(slot) { slot += 1 }
                if let itemIndex = tab.items.firstIndex(where: { $0.id == id }) {
                    if tab.items[itemIndex].slot != slot {
                        tab.items[itemIndex].slot = slot
                        changed = true
                    }
                }
                blocked.insert(slot)
                slot += 1
            }
        }

        guard changed else { return resultIDs }
        mutate { $0.tabs[tabIndex] = tab }
        return resultIDs
    }

    /// Places `ids` at consecutive free grid slots starting at `start` — skipping any
    /// slot held by an item *not* in `ids` — preserving their order. Used when several
    /// items are dropped onto a slot together so they land in a tidy run from the
    /// target instead of scattering. See ANALYSIS.md I4.
    func placeItems(_ ids: [UUID], startingAt start: Int, inTab tabID: UUID) {
        guard !ids.isEmpty else { return }
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            let moving = Set(ids)
            var blocked = Set($0.tabs[ti].items.filter { !moving.contains($0.id) }.map(\.slot))
            var slot = max(0, start)
            for id in ids {
                while blocked.contains(slot) { slot += 1 }   // next slot free of a non-moving item
                if let ii = $0.tabs[ti].items.firstIndex(where: { $0.id == id }) {
                    $0.tabs[ti].items[ii].slot = slot
                }
                blocked.insert(slot)
                slot += 1
            }
        }
    }

    func removeItem(id itemID: UUID, fromTab tabID: UUID) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].items.removeAll { $0.id == itemID }
            }
        }
    }

    func updateItem(_ item: DrawerItem, inTab tabID: UUID) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }),
               let j = $0.tabs[i].items.firstIndex(where: { $0.id == item.id }) {
                $0.tabs[i].items[j] = item
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
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  let ii = $0.tabs[ti].items.firstIndex(where: { $0.id == itemID }) else { return }
            let oldSlot = $0.tabs[ti].items[ii].slot
            guard oldSlot != slot else { return }
            if let occupant = $0.tabs[ti].items.firstIndex(where: { $0.slot == slot }) {
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
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            $0.tabs[ti].items = DrawerGrouping.removingFromGroup($0.tabs[ti].items,
                                                                 childID: childID, groupID: groupID)
        }
    }

    /// Renames group `groupID` (the inline field in the open-group header).
    func renameGroup(groupID: UUID, to name: String, inTab tabID: UUID) {
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            $0.tabs[ti].items = DrawerGrouping.renaming($0.tabs[ti].items, groupID: groupID, to: name)
        }
    }

    /// Reorders a child within its group's sub-grid, with the same swap-or-move-into-a-
    /// gap semantics as `placeItem` one level down.
    func placeItemInGroup(_ itemID: UUID, atSlot slot: Int, groupID: UUID, inTab tabID: UUID) {
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  let gi = $0.tabs[ti].items.firstIndex(where: { $0.id == groupID && $0.kind == .group }),
                  let ii = $0.tabs[ti].items[gi].children.firstIndex(where: { $0.id == itemID }) else { return }
            let oldSlot = $0.tabs[ti].items[gi].children[ii].slot
            guard oldSlot != slot else { return }
            if let occupant = $0.tabs[ti].items[gi].children.firstIndex(where: { $0.slot == slot }) {
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
        // A document written by a newer MacDring (schema version above ours)
        // must never be rewritten by this build: our encoder would silently
        // drop everything it doesn't know about. The in-memory session still
        // works; only persistence is disabled.
        guard document.version <= LauncherDocument.currentVersion else {
            NSLog("MacDring: launcher document is version \(document.version), newer than this build's \(LauncherDocument.currentVersion) — not saving, so the newer document isn't damaged")
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
            NSLog("MacDring: failed to save launcher document: \(error.localizedDescription)")
        }
    }
}
