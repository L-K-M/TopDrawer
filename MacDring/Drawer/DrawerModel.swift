// AppKit dropped: the only symbol used from it was CGRect, which Foundation vends on
// both platforms. Combine is the real thing on macOS; on Linux the module's
// ObservationCompat shim supplies ObservableObject/@Published.
import Foundation
#if canImport(Combine)
import Combine
#endif

/// Observable content + callbacks for the shared drawer panel. The
/// `TabController` swaps these values as different tabs' drawers are shown.
final class DrawerModel: ObservableObject {
    @Published var title: String = ""
    @Published var colorHex: String = "#0A84FF"
    @Published var appearance = DrawerAppearance()
    @Published var actionError: String?
    /// The launcher store's save health (mirrored by `TabController`): non-nil when
    /// layout edits cannot reach disk, shown persistently in the header — unlike the
    /// transient `actionError`.
    @Published var persistenceError: String?
    @Published var isEditingGroupName = false
    @Published var edge: Edge = .right
    /// Inner corners to square so the riding tab joins the drawer flush (set by the
    /// window controller from the tab/drawer geometry). `start`/`end` run along the
    /// inward face: top→bottom for left/right, leading→trailing for top/bottom.
    @Published var squareInnerStart: Bool = false
    @Published var squareInnerEnd: Bool = false
    @Published var items: [DrawerItem] = [] {
        didSet {
            // Keep `openGroupID` honest: if the open group is gone from the new items
            // (dissolved by a pop-out, or removed by a reconcile), drop back to the top
            // level. Otherwise the raw id would linger and misroute reorders/dwell and
            // show a phantom "Move Out of Group" on every top-level item.
            if let gid = openGroupID, !items.contains(where: { $0.id == gid && $0.kind == .group }) {
                openGroupID = nil
            }
            if kind != .clipboard, let selectedItemID,
               !displayedItems.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = nil
            }
        }
    }
    /// The id of the group whose expanded sub-grid is currently open, or `nil` at the
    /// top level. Cleared automatically when that group no longer exists (dissolved,
    /// or gone after a reconcile) — see `items.didSet`.
    @Published var openGroupID: UUID? {
        didSet { if openGroupID != oldValue { selectedItemID = nil } }
    }
    @Published var isDropTargeted: Bool = false
    /// The displayed item or empty grid cell a file drag is currently hovering over.
    /// `nil` means the background (or no active file drag).
    @Published var fileDropTarget: ExternalDropTarget?
    /// External target → frame (in the drawer's content coordinate space), mirrored
    /// from the view so the file-drop delegate can map a drag location **live**.
    /// (The delegate's own captured copy is stale when a drawer springs open
    /// mid-drag, before the grid has reported its frames.)
    var externalDropTargetFrames: [ExternalDropTarget: CGRect] = [:]

    /// The tab's grid size (width = columns, height = rows).
    @Published var columns: Int = 4
    @Published var rows: Int = 2

    /// Whether the open tab is locked (shown as a small lock in the drawer header).
    @Published var locked: Bool = false

    /// What the drawer shows.
    @Published var kind: TabKind = .items
    /// How the drawer arranges items (grid / list) — the open tab's per-tab `layout`
    /// already resolved against the global default, so the view and sizing agree.
    @Published var layout: DrawerLayout = .grid
    /// The note text (for `.notes` tabs): the store's copy, or the last text the
    /// editor reported. The notes editor reconciles against this, so a background
    /// update to it does *not* reset the editor's cursor (see `NotesEditorHostSession`).
    @Published var notes: String = ""
    /// Identity of the open tab. The notes editor treats a change here as "now
    /// showing a different document", which is what distinguishes a new note from
    /// an unrelated refresh of the one on screen.
    @Published var documentID: UUID?
    /// The linked directory (for `.folder` tabs), used by "Open in Finder".
    @Published var folderURL: URL?
    /// Whether the open `.recents` drawer has Top Drawer-owned history that the header
    /// clear button can actually remove. System Spotlight recents are read-only.
    @Published var canClearRecents = false
    @Published var clipboardEntries: [ClipboardEntry] = [] {
        didSet {
            if clipboardError != nil { clipboardError = nil }
            guard kind == .clipboard, let selectedItemID,
                  !clipboardSearchResults.contains(where: { $0.id == selectedItemID }) else { return }
            self.selectedItemID = clipboardSearchResults.first?.id
        }
    }
    @Published var clipboardError: String?
    @Published var clipboardPersistenceError: String?
    /// Whether the live listing was capped (a folder with more than `FolderLister.limit`
    /// entries) — drives the header's "300+" truncation badge.
    @Published var itemsTruncated = false
    @Published var isLoadingListing = false

    /// A transient "Moved N items — Undo" banner shown in the drawer header after a
    /// drop moved files. `nil` when no toast is showing. Set/cleared by the controller.
    @Published var undoToast: DrawerUndo?

    /// Disk items currently being ejected (Eject All), shown with a per-item spinner.
    @Published var ejectingItemIDs: Set<UUID> = []
    /// Fresh items that just arrived this update, shown with a brief sparkle.
    @Published var sparklingItemIDs: Set<UUID> = []

    /// Bumped to force drawer item icons to re-resolve in place even though the
    /// items are unchanged — e.g. the Trash icon (full → empty) after emptying.
    @Published var iconNonce = 0

    /// Bundle IDs of currently-running apps (kept current by `TabController`), so an
    /// application item shows a Dock-style "running" dot. Updated live as apps
    /// launch/quit.
    @Published var runningBundleIDs: Set<String> = []
    // MARK: Type-to-find

    /// The live filter query (type-to-find). Empty = not searching. Bound to the
    /// drawer's filter field, which is auto-focused on open; changing it re-selects the
    /// top result so Return launches a sensible default.
    @Published var searchQuery = "" {
        didSet { if searchQuery != oldValue { selectedItemID = searchResultIDs.first } }
    }
    /// The keyboard-selected result while searching (Up/Down/Return nav).
    @Published var selectedItemID: UUID?

    /// The group whose sub-grid is expanded (nil at the top level; nil too once that
    /// group is dissolved, so the view falls back to the top level automatically).
    var openGroup: DrawerItem? { openGroupID.flatMap { id in items.first { $0.id == id && $0.kind == .group } } }
    /// The items the drawer body shows: an open group's children, else the top level.
    var visibleItems: [DrawerItem] { openGroup?.children ?? items }
    /// The items actually rendered as external drop targets. Search replaces the
    /// current grid/list with flattened results, including matching group children.
    var displayedItems: [DrawerItem] { isSearching ? searchResults : visibleItems }

    /// Clipboard search stays visible as its history grows; item listings offer it
    /// once enough items exist (including group children).
    var isSearchable: Bool {
        kind == .clipboard || (kind != .notes && items.flattenedLaunchable().count >= DrawerSearch.minItemsToShow)
    }
    var isSearching: Bool { !searchQuery.isEmpty }
    /// The items matching the current query — groups flattened to their children so
    /// type-to-find reaches inside them (prefix matches first; see `DrawerSearch`).
    var searchResults: [DrawerItem] { DrawerSearch.filter(items.flattenedLaunchable(), query: searchQuery) }

    var clipboardSearchResults: [ClipboardEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return clipboardEntries }
        return clipboardEntries.filter {
            $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil
        }
    }

    private var searchResultIDs: [UUID] {
        kind == .clipboard ? clipboardSearchResults.map(\.id) : searchResults.map(\.id)
    }

    /// Clears the query and selection (the search bar's ✕, or Esc while searching).
    func clearSearch() {
        searchQuery = ""
        selectedItemID = nil
    }

    /// Moves the keyboard selection among the current results.
    func moveSelection(down: Bool) {
        moveSelection(down ? .down : .up)
    }

    func moveSelection(_ direction: DrawerNavigation.Direction) {
        if kind == .clipboard {
            let ids = clipboardSearchResults.map(\.id)
            let current = selectedItemID.flatMap { ids.firstIndex(of: $0) }
            let down = direction == .down || direction == .right
            if let next = DrawerSearch.nextIndex(count: ids.count, current: current, down: down) {
                selectedItemID = ids[next]
            }
            return
        }
        let items = isSearching ? searchResults : visibleItems.sorted { $0.slot < $1.slot }
        selectedItemID = DrawerNavigation.nextID(in: items, current: selectedItemID,
            direction: direction, columns: columns, layout: isSearching ? .list : layout)
    }

    /// Launches the selected result (Return) — or the top result if none is selected.
    func launchSelection() {
        if kind == .clipboard {
            let results = clipboardSearchResults
            let target = selectedItemID.flatMap { id in results.first { $0.id == id } } ?? results.first
            if let target { onCopyClipboardEntry?(target.id) }
            return
        }
        let results = isSearching ? searchResults : visibleItems.sorted { $0.slot < $1.slot }
        let target = selectedItemID.flatMap { id in results.first { $0.id == id } } ?? results.first
        guard let target else { return }
        if target.isGroup { openGroupID = target.id } else { onLaunch?(target) }
    }

    func previewSelection() {
        guard kind != .clipboard, let selectedItemID,
              let item = displayedItems.first(where: { $0.id == selectedItemID }) else { return }
        if item.kind == .url, let url = item.url, ItemPreviewPolicy.isWebsite(url) {
            onPreviewWebsite?(item)
        } else if item.kind == .file || item.kind == .folder {
            onPreviewItem?(item)
        }
    }

    func isEditingLocked(_ item: DrawerItem) -> Bool {
        if item.containsLockedItems { return true }
        return items.contains { $0.isLocked && $0.children.contains(where: { $0.id == item.id }) }
    }

    func isRemovalLocked(_ item: DrawerItem) -> Bool {
        if isEditingLocked(item) { return true }
        return items.contains {
            $0.children.count <= DrawerGrouping.dissolveThreshold && $0.children.contains(where: { $0.id == item.id })
                && $0.children.contains(where: { $0.id != item.id && $0.isLocked })
        }
    }

    var onLaunch: ((DrawerItem) -> Void)?
    var onRemoveItem: ((DrawerItem) -> Void)?
    var onRevealItem: ((DrawerItem) -> Void)?
    var onPreviewItem: ((DrawerItem) -> Void)?
    var onBrowseFolder: ((DrawerItem) -> Void)?
    var onPreviewWebsite: ((DrawerItem) -> Void)?
    var onLaunchExternally: ((DrawerItem) -> Void)?
    var onOpenWith: ((DrawerItem, URL) -> Void)?
    var onToggleItemLock: ((DrawerItem) -> Void)?
    /// Empty the Trash (Trash item context menu).
    var onEmptyTrash: (() -> Void)?
    /// Rename an item (drawer item context menu).
    var onRenameItem: ((DrawerItem) -> Void)?
    /// Choose a custom icon image for an item.
    var onChangeItemIcon: ((DrawerItem) -> Void)?
    /// Clear an item's custom icon, restoring its default.
    var onResetItemIcon: ((DrawerItem) -> Void)?
    /// Open the generated-icon editor for an item (any item, any tab kind).
    var onCustomizeItemIcon: ((DrawerItem) -> Void)?
    /// Eject a `.disk` item's volume (Disks tab).
    var onEjectItem: ((DrawerItem) -> Void)?
    /// Eject every ejectable volume (Disks tab header button).
    var onEjectAll: (() -> Void)?
    /// Files were dropped on the drawer. Targets carry displayed identity plus an
    /// optional unambiguous top-level placement slot; `nil` is the background.
    var onDropFiles: ((_ urls: [URL], _ target: ExternalDropTarget?) -> Void)?
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    /// Called when a drag-reorder finishes: place `itemID` at grid `slot`.
    var onPlaceItem: ((_ itemID: UUID, _ slot: Int) -> Void)?
    /// Two items were dragged together (drop app onto app) — form a new group, or
    /// extend the target group: `draggedID` dropped onto `targetID`.
    var onGroupItems: ((_ draggedID: UUID, _ targetID: UUID) -> Void)?
    /// A drag-reorder finished *inside* the open group: place `itemID` at the group's
    /// sub-grid `slot`.
    var onPlaceInGroup: ((_ itemID: UUID, _ slot: Int) -> Void)?
    /// Pop `itemID` out of group `groupID` back to the top level (context menu, or a
    /// drag out of the folder).
    var onRemoveFromGroup: ((_ itemID: UUID, _ groupID: UUID) -> Void)?
    /// Rename group `groupID` to `name` (the inline field in the open-group header).
    var onRenameGroup: ((_ groupID: UUID, _ name: String) -> Void)?
    /// Open this tab's settings (drawer header gear).
    var onOpenSettings: (() -> Void)?
    /// Toggle this tab's locked state (drawer header lock).
    var onToggleLocked: (() -> Void)?
    /// Notes text changed (for `.notes` tabs), with the document it belongs to —
    /// the drawer saves against that note, not against the currently open tab,
    /// because an edit can arrive after the drawer has moved on.
    var onNotesChanged: ((String, UUID) -> Void)?
    /// The notes editor asked to open a URL (an explicit Cmd/Ctrl-click on a link).
    /// The editor itself never navigates, so this is the only way a link leaves a note.
    var onOpenNoteLink: ((URL) -> Void)?
    /// Set by the notes editor while it is on screen, cleared on teardown: asks it
    /// to report a pending edit immediately. The drawer calls this as it hides,
    /// because hiding a web view does not reliably produce a visibility change.
    /// Deliberately not `@Published`: it is a capability, not content, and making
    /// it observed would re-render the drawer every time the editor registers.
    var requestNotesFlush: (() -> Void)?
    /// Open the linked directory in Finder (for `.folder` tabs).
    var onOpenFolder: (() -> Void)?
    /// Clear the recent items (for `.recents` tabs).
    var onClearRecents: (() -> Void)?
    var onCopyClipboardEntry: ((UUID) -> Void)?
    var onRemoveClipboardEntry: ((UUID) -> Void)?
    var onClearClipboardHistory: (() -> Void)?

    // MARK: Notes

    /// Adopts an edit the notes editor reported, so `notes` keeps meaning "the
    /// freshest text for the open note".
    ///
    /// This is not bookkeeping: `notes` is what the editor is handed back on every
    /// update pass, and the drawer is invalidated constantly for unrelated reasons
    /// (a screen or preference change, another tab's mutation). Leaving the copy the
    /// drawer opened with in place would make the very next invalidation push it
    /// back as a `replaceDocument` and revert what the user just typed — the store
    /// alone cannot supply it, because saving a note deliberately does not
    /// reconcile (`TabStore.setNotes`).
    ///
    /// An edit for another note — one the editor reported after the drawer moved on,
    /// which the controller still persists against that note — must not become the
    /// open note's text, so it is ignored here.
    ///
    /// Private on purpose: mirroring without persisting loses the edit, so the only
    /// way in is `handleNotesEdit`, which does both.
    private func recordNotesEdit(_ text: String, forDocument documentID: UUID) {
        guard documentID == self.documentID, text != notes else { return }
        notes = text
    }

    /// The single entry point for an edit the notes editor reported: mirror it into
    /// `notes`, then hand it on to be persisted.
    ///
    /// One call rather than two at the call site, because the pairing *is* the fix.
    /// Two adjacent statements say nothing about belonging together, and a call site
    /// that persists without mirroring — a refactor of the pane, or a second editor
    /// surface — silently brings the revert back.
    ///
    /// The mirror is guarded and the notify is not, which is deliberate on both
    /// counts. An edit naming a note the drawer has already left still has to reach
    /// the store for that note, and `TabController` ends a pending quit's wait on
    /// this callback, so an edit it skipped would hold the quit to its timeout.
    func handleNotesEdit(_ text: String, forDocument documentID: UUID) {
        recordNotesEdit(text, forDocument: documentID)
        onNotesChanged?(text, documentID)
    }

    /// The item occupying a grid slot, if any.
    func item(atSlot slot: Int) -> DrawerItem? {
        items.first { $0.slot == slot }
    }

    /// The item occupying a slot in the **currently visible** context — an open
    /// group's children, else the top level. Drives the grid while a group is open.
    func visibleItem(atSlot slot: Int) -> DrawerItem? {
        visibleItems.first { $0.slot == slot }
    }

    /// Builds the external target for a displayed cell. Only the unfiltered top-level
    /// layout can safely use its local slot for top-level placement.
    func externalDropTarget(for item: DrawerItem?, atLocalSlot slot: Int) -> ExternalDropTarget {
        let placementSlot = openGroupID == nil && !isSearching ? slot : nil
        if let item {
            return .occupiedItem(id: item.id, topLevelPlacementSlot: placementSlot)
        }
        return .emptySlot(localSlot: slot, topLevelPlacementSlot: placementSlot)
    }

    /// Resolves an occupied external target only among the items currently displayed.
    /// Empty slots and the background intentionally have no item.
    func item(forExternalDropTarget target: ExternalDropTarget?) -> DrawerItem? {
        guard let target, case .occupiedItem(let id, _) = target else { return nil }
        return displayedItems.first { $0.id == id }
    }
}

/// A pending "Undo" action for the drawer's move toast: the message to show and the
/// closure that reverses the move. Not `Equatable` (it carries a closure); the
/// `@Published var undoToast` just swaps the whole value.
struct DrawerUndo {
    let message: String
    let action: () -> Void
}
