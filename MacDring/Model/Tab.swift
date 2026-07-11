import Foundation

/// A screen-edge tab and the drawer of items behind it. The unit of the whole
/// app: a colored pill on an edge that expands into a grid/list of launchables.
struct Tab: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    /// The tab's color (`#RRGGBB`). The marquee per-tab customization.
    var colorHex: String
    var glyph: TabGlyph
    var anchor: ScreenAnchor
    var items: [DrawerItem]
    var behavior: TabBehavior
    var hotkey: HotkeySpec?

    /// The drawer's grid size for this tab (width = columns, height = rows). Items
    /// are placed within this grid; it grows if items are placed beyond it. For a
    /// notes tab it sizes the text area.
    var gridColumns: Int {
        didSet {
            let bounded = PersistedLayoutBounds.clampedGridColumns(gridColumns)
            if gridColumns != bounded { gridColumns = bounded }
        }
    }
    var gridRows: Int {
        didSet {
            let bounded = PersistedLayoutBounds.clampedGridRows(gridRows)
            if gridRows != bounded { gridRows = bounded }
        }
    }

    /// When locked, the tab can't be dragged to a new position.
    var locked: Bool

    /// What this tab's drawer shows (items / notes / folder).
    var kind: TabKind

    /// How this tab's drawer arranges its items — **grid** or **list**. A per-tab
    /// choice (there's no global default); date-ranked tabs (Fresh, system Recents)
    /// read well as a date-ordered list.
    var layout: DrawerLayout

    /// The note text for a `.notes` tab.
    var notes: String

    /// The linked directory for a `.folder` tab (bookmark + resolved-path fallback).
    var folderBookmark: Data?
    var folderURL: URL?

    /// How a `.folder` tab's listing is ordered, and whether it includes hidden files.
    var folderSort: FolderSort
    var folderShowsHidden: Bool

    /// What a `.recents` tab includes: Top Drawer's own launch history, the system-wide
    /// Spotlight recents, or both. Default `.macDring` keeps the original behavior.
    var recentsSource: RecentsSource

    /// Per-target generated-icon overrides for this tab's **live** items
    /// (folder/disks/network/cloud listings), keyed by the item's path. Persistent
    /// `.items` carry their override on the item itself; live items are rebuilt each
    /// open, so their overrides live here and are re-applied at list time.
    var iconStyles: [String: IconStyle]

    init(id: UUID = UUID(),
         title: String,
         colorHex: String,
         glyph: TabGlyph = .default,
         anchor: ScreenAnchor,
         items: [DrawerItem] = [],
         behavior: TabBehavior = .default,
         hotkey: HotkeySpec? = nil,
         gridColumns: Int = 4,
         gridRows: Int = 2,
         locked: Bool = false,
         kind: TabKind = .items,
         layout: DrawerLayout = .grid,
         notes: String = "",
         folderBookmark: Data? = nil,
         folderURL: URL? = nil,
         folderSort: FolderSort = .name,
         folderShowsHidden: Bool = false,
         recentsSource: RecentsSource = .macDring,
         iconStyles: [String: IconStyle] = [:]) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.glyph = glyph
        self.anchor = anchor
        self.items = items
        self.behavior = behavior
        self.hotkey = hotkey
        self.gridColumns = PersistedLayoutBounds.clampedGridColumns(gridColumns)
        self.gridRows = PersistedLayoutBounds.clampedGridRows(gridRows)
        self.locked = locked
        self.kind = kind
        self.layout = layout
        self.notes = notes
        self.folderBookmark = folderBookmark
        self.folderURL = folderURL
        self.folderSort = folderSort
        self.folderShowsHidden = folderShowsHidden
        self.recentsSource = recentsSource
        self.iconStyles = iconStyles
    }

    /// Decodes forward-compatibly: only `anchor` is allowed to fail the tab
    /// (a tab without a place on screen can't exist). Every enum-like field —
    /// where a **newer** Top Drawer may have written a raw value this build
    /// doesn't know — degrades to its default via `decodeLenient` instead of
    /// throwing, and one unreadable item is dropped (`FailableDrawerItem`)
    /// rather than taking the whole tab — and, via `FailableTab` + the next
    /// autosave, the user's arrangement — down with it. Groups made too small
    /// by that filtering are dissolved so invalid containers don't survive.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Tab"
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#0A84FF"
        glyph = c.decodeLenient(TabGlyph.self, forKey: .glyph, fallback: .default)
        anchor = try c.decode(ScreenAnchor.self, forKey: .anchor)
        let decodedItems = c.decodeLenient([FailableDrawerItem].self, forKey: .items, fallback: [])
            .compactMap(\.item)
        items = DrawerGrouping.dissolvingSmallGroups(decodedItems)
        behavior = c.decodeLenient(TabBehavior.self, forKey: .behavior, fallback: .default)
        hotkey = c.decodeLenient(HotkeySpec?.self, forKey: .hotkey, fallback: nil)
        gridColumns = PersistedLayoutBounds.clampedGridColumns(
            try c.decodeIfPresent(Int.self, forKey: .gridColumns) ?? 4
        )
        gridRows = PersistedLayoutBounds.clampedGridRows(
            try c.decodeIfPresent(Int.self, forKey: .gridRows) ?? 2
        )
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        kind = c.decodeLenient(TabKind.self, forKey: .kind, fallback: .items)
        // Older documents wrote a per-tab `useGlobal` (or nothing); both fall back to
        // `.grid`, the layout the global default used to be.
        layout = c.decodeLenient(DrawerLayout.self, forKey: .layout, fallback: .grid)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        folderBookmark = try c.decodeIfPresent(Data.self, forKey: .folderBookmark)
        folderURL = try c.decodeIfPresent(URL.self, forKey: .folderURL)
        folderSort = c.decodeLenient(FolderSort.self, forKey: .folderSort, fallback: .name)
        folderShowsHidden = try c.decodeIfPresent(Bool.self, forKey: .folderShowsHidden) ?? false
        recentsSource = c.decodeLenient(RecentsSource.self, forKey: .recentsSource, fallback: .macDring)
        iconStyles = c.decodeLenient([String: IconStyle].self, forKey: .iconStyles, fallback: [:])
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, colorHex, glyph, anchor, items, behavior, hotkey
        case gridColumns, gridRows, locked, kind, layout, notes, folderBookmark, folderURL
        case folderSort, folderShowsHidden, recentsSource, iconStyles
    }
}
