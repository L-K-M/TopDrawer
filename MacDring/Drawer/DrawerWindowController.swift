import AppKit
import SwiftUI

/// The drawer's hosting view, which also serves as the AppKit **drag destination**
/// for file drops. SwiftUI's `.onDrop` is unreliable inside this borderless panel
/// (especially nested in a `ScrollView`) and gives no hovered location — the same
/// reason reordering uses a `DragGesture` instead. So drops are handled here at the
/// AppKit level: the drag location is mapped to a grid slot via `model.slotFrames`
/// (which the SwiftUI content reports in this view's coordinate space) and routed
/// through `model.onDropFiles`. Also accepts the first mouse click while non-key.
private final class DrawerHostingView: NSHostingView<DrawerView> {
    /// Wired by the controller right after construction (the same model the
    /// SwiftUI `DrawerView` observes), used to read slot frames + the tab kind and
    /// to route drops. The controller also calls `registerForDraggedTypes`.
    var model: DrawerModel?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The grid slot under a window-space drag `location` (nearest if none contains
    /// it). Converts to this view's top-left coordinate space to match the frames
    /// the SwiftUI content reports into `model.slotFrames`.
    private func slot(at location: NSPoint, _ model: DrawerModel) -> Int? {
        var p = convert(location, from: nil)            // window → this view
        if !isFlipped { p.y = bounds.height - p.y }      // normalize to top-left (SwiftUI)
        let point = CGPoint(x: p.x, y: p.y)
        let frames = model.slotFrames
        guard !frames.isEmpty else { return nil }
        if let hit = frames.first(where: { $0.value.contains(point) })?.key { return hit }
        // Only snap to the nearest slot when within (or just outside) the grid; a
        // drop on the header/margins returns nil → slot -1 (generic add to the tab),
        // so it can't accidentally land "inside" the nearest folder.
        let grid = frames.values.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -24, dy: -24)
        guard grid.contains(point) else { return nil }
        return frames.min { sqDist($0.value, point) < sqDist($1.value, point) }?.key
    }

    private func sqDist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = p.x - r.midX, dy = p.y - r.midY
        return dx * dx + dy * dy
    }

    /// The model iff this drag is acceptable here (items/folder tab + has file URLs
    /// or web links). Notes, Disks, Network, Cloud, Recents, and Fresh tabs are
    /// read-only live listings, so they take no drops. A folder tab whose directory
    /// is unset or unresolvable takes none either — advertising a copy drop that
    /// `handleFileDrop` would then silently swallow is worse than refusing it.
    private func droppableModel(_ sender: NSDraggingInfo) -> DrawerModel? {
        guard let model, model.kind != .notes, model.kind != .disks,
              model.kind != .network, model.kind != .cloud, model.kind != .recents,
              model.kind != .fresh,
              !(model.kind == .folder && model.folderURL == nil),
              sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                      options: pasteboardOptions(for: model))
        else { return nil }
        return model
    }

    /// Folder drawers file dropped items into the mirrored directory, so accepting
    /// browser URLs would show a valid drop and then do nothing. Items drawers can
    /// still accept both file URLs and web links because they create launcher items.
    private func pasteboardOptions(for model: DrawerModel) -> [NSPasteboard.ReadingOptionKey: Any] {
        [.urlReadingFileURLsOnly: model.kind == .folder]
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }

    private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let model = droppableModel(sender) else { return [] }
        // Equality-guard both writes: `draggingUpdated` fires per mouse-move, and a
        // `@Published` setter emits objectWillChange even for an identical value —
        // unguarded, every drag frame re-invalidated the whole drawer twice.
        let target = slot(at: sender.draggingLocation, model)   // drives the per-slot highlight
        if model.fileDropSlot != target { model.fileDropSlot = target }
        // Whole-drawer highlight: even over the header/margins (no slot under
        // the cursor) the drag is acceptable — releasing adds to the tab — and
        // the outline brightening is the only feedback saying so.
        if !model.isDropTargeted { model.isDropTargeted = true }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model?.fileDropSlot = nil
        model?.isDropTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        model?.fileDropSlot = nil
        model?.isDropTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        droppableModel(sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let model = droppableModel(sender) else { return false }
        let target = slot(at: sender.draggingLocation, model) ?? -1
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                          options: pasteboardOptions(for: model)) as? [URL]) ?? []
        model.fileDropSlot = nil
        model.isDropTargeted = false
        guard !urls.isEmpty else { return false }
        model.onDropFiles?(urls, target)   // routed by TabController (open-with / move-in / add)
        return true
    }
}

/// A borderless panel that is still allowed to become key. Becoming key (while
/// staying a non-activating panel, so the *app* never activates) is what lets
/// SwiftUI drag-to-reorder and the Esc key work inside the drawer.
private final class KeyableDrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the single shared drawer panel, positions it adjacent to whichever tab
/// is open (growing away from the edge), and keeps it sized to its content.
/// Non-activating so it never steals focus from the user's frontmost app.
final class DrawerWindowController {

    let model = DrawerModel()
    private let preferences: Preferences
    private let panel: NSPanel
    private let hostingView: DrawerHostingView

    private(set) var isVisible = false
    /// The drawer's fully-open (flush-to-edge) frame for the current tab. The tab
    /// is positioned against this, and the slide animation runs to/from it.
    private(set) var openFrame: CGRect = .zero
    private var currentEdge: Edge = .right
    private var currentScreen: NSScreen?
    private var currentTabFrame: CGRect = .zero

    init(preferences: Preferences) {
        self.preferences = preferences

        let hosting = DrawerHostingView(rootView: DrawerView(model: model, preferences: preferences))
        hosting.model = model
        hosting.registerForDraggedTypes([.fileURL, .URL])
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        self.hostingView = hosting

        let panel = KeyableDrawerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.level = preferences.tabWindowLevel.drawerWindowLevel   // above its tab, within the chosen mode
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let container = NSView(frame: panel.frame)
        container.autoresizesSubviews = true
        hosting.frame = container.bounds
        container.addSubview(hosting)
        panel.contentView = container
        self.panel = panel
    }

    /// The drawer's window — used by the controller to test click-outside hits.
    var window: NSWindow { panel }
    var frame: CGRect { panel.frame }

    // MARK: Presentation

    /// How far the drawer nudges (inward) while fading in/out.
    private static let nudge: CGFloat = 22

    /// Shows the drawer for `tab` over `duration` seconds (0 = instant) with a fade
    /// + small inward slide. The slide stays on the drawer's own screen, so it
    /// never bleeds onto an adjacent display at a shared edge.
    func show(tab: Tab, tabFrame: CGRect, edge: Edge, on screen: NSScreen, duration: TimeInterval) {
        panel.level = preferences.tabWindowLevel.drawerWindowLevel
        apply(tab: tab)
        model.clearSearch()   // each open starts unfiltered
        model.edge = edge
        currentEdge = edge
        currentScreen = screen
        currentTabFrame = tabFrame
        openFrame = computeOpenFrame(in: screen.visibleFrame)

        if duration > 0 {
            panel.setFrame(EdgeLayout.nudgedDrawerFrame(edge: edge, openFrame: openFrame, by: Self.nudge), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.makeKey()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(openFrame, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.setFrame(openFrame, display: true)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
        isVisible = true
    }

    /// Refreshes content for the currently shown tab (e.g. after a drop / reorder)
    /// and re-positions instantly (no animation). Live note text is preserved: a
    /// refresh can be triggered by an *unrelated* reconcile (a screen or preference
    /// change, or a mutation to another tab) while the user is typing, and the model
    /// is the freshest source for an open notes drawer — overwriting it would reset
    /// the editor's selection / in-flight input. See ANALYSIS.md B7.
    func refresh(tab: Tab, tabFrame: CGRect, edge: Edge, on screen: NSScreen) {
        guard isVisible else { return }
        apply(tab: tab, preserveLiveNotes: true)
        model.edge = edge
        currentEdge = edge
        currentScreen = screen
        currentTabFrame = tabFrame
        openFrame = computeOpenFrame(in: screen.visibleFrame)
        panel.setFrame(openFrame, display: true)
    }

    /// Replaces the open drawer's items with an asynchronously-gathered live listing
    /// (Spotlight: the Fresh tab and the system Recents source) and resizes the panel
    /// to fit — **without** re-running `apply` (which would re-issue the query). Called
    /// by `TabController` when a query finishes; the controller re-seats the riding tab.
    func updateLiveItems(_ items: [DrawerItem]) {
        guard isVisible, let screen = currentScreen else { return }
        model.items = items
        if model.kind == .fresh { model.sparklingItemIDs = sparkleIDs(for: items) }
        openFrame = computeOpenFrame(in: screen.visibleFrame)
        panel.setFrame(openFrame, display: true)
    }

    /// Hides the drawer over `duration` seconds with a fade + small inward slide.
    func hide(duration: TimeInterval) {
        guard isVisible else { return }
        isVisible = false
        guard duration > 0 else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            model.items = []
            model.clearSearch()
            return
        }
        let end = EdgeLayout.nudgedDrawerFrame(edge: currentEdge, openFrame: openFrame, by: Self.nudge)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Skip if a new open happened during the close animation.
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1   // reset while hidden, ready for next open
            self.model.items = []
            self.model.clearSearch()
        })
    }

    /// Loads `tab` into the model. When `preserveLiveNotes` is true (a refresh of an
    /// already-open drawer), a notes tab's live `model.notes` is left untouched so a
    /// background reconcile can't clobber what the user is typing.
    /// A Fresh item counts as "just landed" (and gets a sparkle) when its Date Added
    /// is within this window of now.
    private static let sparkleWindow: TimeInterval = 300

    /// The IDs of `items` that landed within `sparkleWindow` of now — for the Fresh
    /// tab's arrival sparkle.
    private func sparkleIDs(for items: [DrawerItem], now: Date = Date()) -> Set<UUID> {
        Set(items.filter { ($0.date.map { now.timeIntervalSince($0) } ?? .infinity) <= Self.sparkleWindow }
            .map(\.id))
    }

    private func apply(tab: Tab, preserveLiveNotes: Bool = false) {
        model.fileDropSlot = nil
        model.isDropTargeted = false
        model.slotFrames = [:]
        model.itemsTruncated = false
        model.sparklingItemIDs = []
        model.title = tab.title
        model.colorHex = tab.colorHex
        model.columns = max(1, tab.gridColumns)
        model.rows = max(1, tab.gridRows)
        model.locked = tab.locked
        model.kind = tab.kind
        model.layout = tab.layout
        model.canClearRecents = tab.kind == .recents
            && tab.recentsSource.includesMacDring
            && !RecentsStore.shared.items.isEmpty
        switch tab.kind {
        case .items:
            model.items = tab.items
            model.notes = ""
            model.folderURL = nil
        case .folder:
            // Live listings re-apply the tab's per-target icon overrides each open.
            let listing = FolderLister.listing(of: tab)
            model.items = listing.items.applyingIconStyles(from: tab.iconStyles)
            model.itemsTruncated = listing.truncated
            model.notes = ""
            model.folderURL = FolderLister.resolveFolder(tab)
        case .disks:
            model.items = DisksLister.contents(of: tab).applyingIconStyles(from: tab.iconStyles)
            model.notes = ""
            model.folderURL = nil
        case .network:
            model.items = NetworkLister.contents(of: tab).applyingIconStyles(from: tab.iconStyles)
            model.notes = ""
            model.folderURL = nil
        case .cloud:
            model.items = CloudLister.contents(of: tab).applyingIconStyles(from: tab.iconStyles)
            model.notes = ""
            model.folderURL = nil
        case .recents:
            // MacDring's own history shows immediately; a `system`/`both` source folds
            // in the Spotlight recents asynchronously via `updateLiveItems`.
            model.items = RecentsLister.contents(of: tab).applyingIconStyles(from: tab.iconStyles)
            model.notes = ""
            model.folderURL = nil
        case .fresh:
            // Works even with Spotlight off: a direct, by-Date-Added scan of the
            // landing zones fills the drawer immediately. The controller's Spotlight
            // watch then merges in any deeper (sub-folder) hits via `updateLiveItems`
            // when the index is available. See `FreshScanner` / `FreshLister.merge`.
            model.items = FreshLister.items(from: FreshScanner.results(scopes: FreshLister.scopes(),
                                                                       limit: FreshLister.limit))
                .applyingIconStyles(from: tab.iconStyles)
            model.sparklingItemIDs = sparkleIDs(for: model.items)
            model.notes = ""
            model.folderURL = nil
        case .notes:
            model.items = []
            if !preserveLiveNotes {
                model.notes = tab.notes
                model.notesPreview = true   // a fresh open starts in the rendered view, not the editor
            }
            model.folderURL = nil
        }
    }

    /// The drawer's flush-to-edge open frame, sized deterministically from the
    /// item count + appearance (not SwiftUI `fittingSize`, which is unreliable for
    /// a ScrollView/LazyVGrid). `DrawerView` fills it.
    private func computeOpenFrame(in visibleFrame: CGRect) -> CGRect {
        let size: CGSize
        if model.kind == .notes {
            size = DrawerMetrics.notesSize(columns: model.columns, rows: model.rows,
                                           iconSize: CGFloat(preferences.iconSize), in: visibleFrame)
        } else {
            size = DrawerMetrics.contentSize(
                itemCount: model.items.count,
                maxSlot: model.items.map(\.slot).max() ?? -1,
                configuredRows: model.rows,
                layout: model.layout,
                iconSize: CGFloat(preferences.iconSize),
                columns: model.columns,
                searchable: model.isSearchable,
                in: visibleFrame
            )
        }
        // Keep the drawer long enough along the edge that the tab joins its *flat*
        // inner face rather than a rounded corner. The straight run of that face is
        // (extent − 2·radius); make it at least the tab's length so the tab — when
        // centered on the drawer along the edge — meets it flush, with no rounded
        // notch at the join (see the "tab doesn't attach to the drawer" report).
        var content = size
        let radius = CGFloat(preferences.cornerRadius)
        let tabLength = currentEdge.isVertical ? currentTabFrame.height : currentTabFrame.width
        let minExtent = tabLength + 2 * radius
        if currentEdge.isVertical {
            content.height = max(content.height, minExtent)
        } else {
            content.width = max(content.width, minExtent)
        }
        let frame = EdgeLayout.openDrawerFrame(edge: currentEdge, tabFrame: currentTabFrame, contentSize: content, in: visibleFrame)

        // When the drawer is clamped toward a screen edge the tab is no longer
        // centered on it and ends up beside an inner corner; square that corner so
        // the tab still joins flush (the minExtent run only covers the centered case).
        let corners = EdgeLayout.drawerInnerCornersToSquare(edge: currentEdge, tabFrame: currentTabFrame,
                                                            drawerFrame: frame, radius: radius)
        model.squareInnerStart = corners.start
        model.squareInnerEnd = corners.end
        return frame
    }
}
