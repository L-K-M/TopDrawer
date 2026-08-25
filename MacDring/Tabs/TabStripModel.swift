// AppKit dropped: this model uses only Foundation and project types (verified — no
// AppKit or Core Graphics symbols). Combine is the real thing on macOS; on Linux the
// module's ObservationCompat shim supplies ObservableObject/@Published.
import Foundation
#if canImport(Combine)
import Combine
#endif

/// Observable visual state for a single tab pill, plus the interaction callbacks
/// the `TabWindowController` wires up. Updating these `@Published` properties
/// re-renders the SwiftUI `TabStripView` in place (no window rebuild).
final class TabStripModel: ObservableObject {
    @Published var title: String
    @Published var colorHex: String
    @Published var glyph: TabGlyph
    @Published var edge: Edge
    @Published var acceptsWebURLDrops: Bool
    /// Whether this pill takes *file* drops at all. Only items and folder tabs do —
    /// the live listings (notes/disks/network/cloud/recents/fresh) are read-only,
    /// and advertising a drop that would be silently discarded is a lie told in
    /// drop-highlight form.
    @Published var acceptsFileDrops: Bool
    /// The drawer for this tab is currently open (drives the pill highlight).
    @Published var isOpen: Bool = false
    /// A file/app is being dragged over the pill (drives the drop highlight).
    @Published var isDropTargeted: Bool = false
    /// Something landed recently (a Fresh tab whose newest item is within the recent
    /// window) — drives the "just landed" dot on the closed pill.
    @Published var hasRecentArrival: Bool = false

    // Interaction callbacks (set by the window controller).
    var onTap: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDropURLs: (([URL]) -> Void)?
    /// A file drag entered (true) or left (false) the pill — used to spring-open
    /// the drawer so the user can drop onto its contents.
    var onDragHover: ((Bool) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragChanged: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onRequestSettings: (() -> Void)?
    var onDelete: (() -> Void)?
    /// Move the tab to a different screen edge (pill context menu).
    var onMoveToEdge: ((Edge) -> Void)?

    init(title: String, colorHex: String, glyph: TabGlyph, edge: Edge,
         acceptsWebURLDrops: Bool, acceptsFileDrops: Bool) {
        self.title = title
        self.colorHex = colorHex
        self.glyph = glyph
        self.edge = edge
        self.acceptsWebURLDrops = acceptsWebURLDrops
        self.acceptsFileDrops = acceptsFileDrops
    }
}
