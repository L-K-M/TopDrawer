import AppKit
import Combine
import UniformTypeIdentifiers

/// The orchestrator. Reconciles the stored tabs against the live display set
/// into on-screen tab windows, owns the shared drawer, and routes every
/// interaction (click, hover, drag-to-reposition, drop, hotkey, launch).
final class TabController {

    private let store: TabStore
    private let preferences: Preferences
    private let registry: DisplayRegistry
    private let drawer: DrawerWindowController

    /// Presents the generated-icon editor (built lazily on first use).
    private lazy var iconEditor = IconEditorWindowController()
    /// Identifies the editor allowed to mutate/reopen its originating drawer. A newer
    /// editor invalidates callbacks from the window it replaces.
    private var iconEditorSessionID: UUID?

    private var tabWindows: [UUID: TabWindowController] = [:]
    private var hotkeys: [UUID: (hotkey: CarbonHotkey, spec: HotkeySpec)] = [:]
    /// Specs macOS already refused to register this session (a system-reserved combo,
    /// or one another app/tab owns). Cached so a reconcile doesn't re-attempt — and
    /// re-log — the same failing spec on every store mutation; cleared when the spec
    /// changes so a new combination is retried.
    private var failedHotkeySpecs: [UUID: HotkeySpec] = [:]
    private var openTabID: UUID?
    /// A new identity for every successful `openDrawer` call. It distinguishes a
    /// reopened drawer from the previous session even when the tab id is unchanged.
    private var drawerSessionID: UUID?
    /// Only the newest launch request in the current drawer session may apply its
    /// completion; a second launch supersedes the first.
    private var activeLaunchRequestID: UUID?
    /// Advances on each successful drawer open and each real drawer close. Toggle
    /// requests flow through those paths, so a snapshot detects intervening drawer
    /// activity even when the drawer ends up closed again.
    private var drawerInteractionGeneration: UInt = 0
    private var hotkeyCounter: UInt32 = 1

    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var pendingHoverClose: DispatchWorkItem?
    private var pendingSpringOpen: DispatchWorkItem?
    private var pendingSpringOpenTabID: UUID?
    private var undoToastClearItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// Observers for volume mount/unmount/rename, so an open Disks/Network drawer
    /// reflects the live set of mounted volumes. Torn down in `saveAndTeardown`.
    private var volumeObservers: [NSObjectProtocol] = []

    /// Live-refresh watch on the open folder tab's directory (FSEvents via a
    /// `DispatchSource`); `nil` when no folder drawer is open.
    private var folderWatch: DispatchSourceFileSystemObject?
    private var folderWatchPath: String?
    /// Watches the home Trash so the Trash item's icon (full/empty) and count badge
    /// update live when Finder empties it. Lives for the controller's lifetime.
    private var trashWatch: DispatchSourceFileSystemObject?
    private var pendingFolderRefresh: DispatchWorkItem?
    /// Coalesces bursts of Trash directory events into one icon refresh.
    private var pendingTrashRefresh: DispatchWorkItem?
    /// A light repeating scan that lights the Fresh tab pill's "just landed" dot;
    /// runs only while a Fresh tab exists.
    private var freshBadgeTimer: Timer?
    /// How recently a Fresh item must have arrived to light the pill dot.
    private static let freshRecentWindow: TimeInterval = 20 * 60

    /// One-shot Spotlight lookup backing the open **Fresh** tab and the **system**
    /// source of a Recents tab; cancelled when the drawer closes or another tab opens.
    private let spotlight = SpotlightQuery()
    /// The tab the `spotlight` query is currently gathering for, so an unrelated
    /// reconcile doesn't cancel-and-restart (and thereby starve) an in-flight gather.
    private var spotlightWatchTabID: UUID?
    /// A dedicated Spotlight lookup for the Fresh pill dot, so the badge never
    /// competes with (or restarts) the open drawer's query.
    private let freshBadgeSpotlight = SpotlightQuery()

    /// Observers for app launch/terminate, so application items show a live "running"
    /// dot. Torn down in `saveAndTeardown`.
    private var runningAppObservers: [NSObjectProtocol] = []

    /// Edge-hover monitors (no permission needed — mouse only) that drive
    /// Dock-style auto-hide / auto-fade reveal. Active only while a concealable tab
    /// is shown and no drawer is open. See `refreshConcealment`.
    private var revealMonitorGlobal: Any?
    private var revealMonitorLocal: Any?
    /// Per-tab delayed re-conceal work, so a tab doesn't snap shut the instant the
    /// cursor leaves its reveal zone.
    private var pendingReConceal: [UUID: DispatchWorkItem] = [:]
    /// The tab currently being dragged, excluded from concealment so it can't slide
    /// out from under the cursor mid-drag.
    private var draggingTabID: UUID?
    /// How far past a tab's resting footprint the cursor still counts as "hovering"
    /// it (an easier target than the thin revealed sliver).
    private static let revealSlop: CGFloat = 6
    /// A more generous reveal margin used while a *file drag* nears a concealed tab's
    /// edge, so spring-loading has a real pill to target rather than a 3 pt sliver.
    private static let peekSlop: CGFloat = 60
    /// The drag pasteboard's `changeCount` stamped at the latest observed mouse-down.
    /// A drag only counts as a *file* drag when the count has advanced past this —
    /// the pasteboard retains the previous drag's files, so content alone would
    /// false-positive the peek on every plain window drag / text selection.
    private var dragPasteboardCountAtPress = NSPasteboard(name: .drag).changeCount
    /// Cached "does the drag pasteboard hold file URLs" answer for a given
    /// `changeCount`, so the out-of-process read runs once per drag session rather
    /// than once per mouse-moved event.
    private var dragPasteboardCanReadFiles: (count: Int, canRead: Bool)?
    /// The guide the dragged tab is currently magnetized to, so the alignment haptic
    /// fires once per snap rather than every mouse-move while snapped.
    private var lastSnapGuide: Double?
    /// Delay before an idle tab re-conceals after the cursor leaves its zone.
    private static let reConcealDelay: TimeInterval = 0.45
    /// The pill's along-edge length captured at drag start, kept constant while
    /// previewing snaps to different edges.
    private var dragLength: CGFloat = 60
    /// Whether the tab currently being dragged is locked (won't move).
    private var dragLocked = false

    /// Invoked to open Settings for a tab (the tab's context menu or the drawer's
    /// gear). `nil` opens Settings without selecting a tab. Wired by `AppDelegate`.
    var onOpenSettings: ((UUID?) -> Void)?

    init(store: TabStore, preferences: Preferences, registry: DisplayRegistry) {
        self.store = store
        self.preferences = preferences
        self.registry = registry
        self.drawer = DrawerWindowController(preferences: preferences)

        wireDrawer()
        startVolumeMonitoring()
        startRunningAppMonitoring()
        startTrashWatch()
        store.onChange = { [weak self] in self?.reconcile() }
        registry.onChange = { [weak self] in self?.reconcile() }
        // A preference change reconciles every tab window (re-measure + reposition,
        // and re-list every folder tab). Dragging an appearance slider fires
        // `objectWillChange` continuously, so debounce to coalesce a burst into a
        // single reconcile once the value settles — `objectWillChange` fires *before*
        // the change, and a debounced main-queue delivery reads the updated value.
        preferences.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)
    }

    func start() { reconcile() }

    // MARK: Reconcile

    /// Brings the on-screen windows in line with the stored tabs and the current
    /// displays. Called on every store change, display change, and appearance
    /// change. See PLAN.md §6 for the park-vs-move-to-main policy.
    func reconcile() {
        let tabs = store.tabs
        let liveIDs = Set(tabs.map(\.id))

        for (id, wc) in tabWindows where !liveIDs.contains(id) {
            wc.close()
            tabWindows[id] = nil
            unregisterHotkey(id)
            cancelReConceal(id)
            if openTabID == id { closeDrawer() }
        }

        for tab in tabs {
            let wc = tabWindows[tab.id] ?? makeWindow(for: tab)
            tabWindows[tab.id] = wc
            wc.update(tab: tab)

            if let screen = registry.screen(for: tab.anchor.displayUUID) {
                wc.place(on: screen)
                wc.show()
            } else if preferences.disconnectPolicy == .moveToMain, let primary = DisplayRegistry.primaryScreen {
                wc.place(on: primary)
                wc.show()
            } else {
                wc.hide()                      // park until the display returns
                if openTabID == tab.id { closeDrawer() }
            }
            registerHotkeyIfNeeded(for: tab)
        }

        deOverlapStackedTabs()
        restackTabs()
        refreshOpenDrawer()
        refreshConcealment(animated: false)
        updateFreshBadgeTimer()
    }

    /// Spaces tabs that share a display + edge so they don't render on top of each
    /// other. Each tab keeps its fractional position; only a tab that would overlap
    /// one already placed snaps to the nearest legal gap. Tabs are placed in stacking
    /// order (`order`, then `position`), so the most-recently-stacked tab — the one
    /// just dragged or added, bumped to the top `order` — is the one that yields,
    /// while the tabs already there stay put.
    ///
    /// Each settled position is **persisted back** (without re-notifying) so the
    /// stored layout is itself legal. That makes the pass idempotent: a later
    /// reconcile — or a neighbour being dragged away — re-derives the same frames and
    /// nothing shifts. Without it, a tab's stored position could stay overlapping and
    /// get re-snapped differently each time, which is what made other tabs jump.
    ///
    /// The open tab is left riding on the drawer face; its new resting frame takes
    /// effect when it closes. See PLAN.md §5.
    private func deOverlapStackedTabs() {
        struct Key: Hashable { let screen: Int; let edge: Edge }
        var groups: [Key: [(wc: TabWindowController, tab: Tab)]] = [:]

        for (id, wc) in tabWindows {
            guard wc.isShown,
                  let screen = wc.currentScreen,
                  let number = screenNumber(screen),
                  let tab = store.tab(id: id) else { continue }
            groups[Key(screen: number, edge: tab.anchor.edge), default: []].append((wc, tab))
        }

        for (key, group) in groups where group.count > 1 {
            let sorted = group.sorted {
                ($0.tab.anchor.order, $0.tab.anchor.position, $0.tab.id.uuidString)
                    < ($1.tab.anchor.order, $1.tab.anchor.position, $1.tab.id.uuidString)
            }
            guard let visible = sorted.first?.wc.currentScreen?.visibleFrame else { continue }
            var placed: [CGRect] = []
            for entry in sorted {
                let incoming = entry.wc.restingFrame
                let snapped = EdgeLayout.snappedAlongEdge(incoming: incoming, fixed: placed,
                                                          edge: key.edge, gap: EdgeLayout.minTabGap, in: visible)
                entry.wc.setRestingFrame(snapped)
                placed.append(snapped)
                // Persist the settled position only while the tab is sitting on its
                // *own* anchored display. A pill displaced here by the move-to-main
                // policy is a guest: its anchor still names the disconnected display,
                // and writing this screen's settled fraction into it would corrupt
                // the spot it must restore to when that display returns ("stable
                // restore is sacred"). Guests are de-overlapped on screen only.
                if let anchored = registry.screen(for: entry.tab.anchor.displayUUID),
                   screenNumber(anchored) == key.screen {
                    persistSettledPosition(snapped, was: incoming, edge: key.edge, in: visible, tab: entry.tab)
                }
            }
        }
    }

    /// Writes a de-overlapped frame's fractional position back onto its tab — but only
    /// when the snap actually moved it (beyond float noise) — so the stored layout
    /// stays legal. Uses `notify: false`: this runs mid-reconcile, and the point is to
    /// settle the layout *without* kicking off another one.
    private func persistSettledPosition(_ snapped: CGRect, was incoming: CGRect,
                                        edge: Edge, in visible: CGRect, tab: Tab) {
        guard abs(snapped.minX - incoming.minX) > 0.5 || abs(snapped.minY - incoming.minY) > 0.5 else { return }
        let position = EdgeLayout.position(forPoint: CGPoint(x: snapped.midX, y: snapped.midY),
                                           edge: edge, in: visible)
        var anchor = tab.anchor
        anchor.position = position
        store.setAnchor(anchor, forTab: tab.id, notify: false)
    }

    /// Gives tabs that share a display + edge a predictable z-order, so where they
    /// overlap (allowed once `minTabGap` goes negative) the result is always drawn the
    /// same way: the **leading** tab — top on a vertical edge, left on a horizontal one
    /// — sits in front of the ones after it, reading top-to-bottom / left-to-right.
    ///
    /// The open tab is skipped — it sits flush *beside* its own drawer, which floats
    /// above the pills, so its z among them doesn't matter — and every other shown tab
    /// is restacked. Called after layout and when a drawer opens or closes, so the
    /// order is restored even after a reconcile's `show()` re-fronts the pills while a
    /// drawer is open. Pure window ordering — frames are untouched.
    private func restackTabs() {
        struct Key: Hashable { let screen: Int; let edge: Edge }
        var groups: [Key: [(id: UUID, wc: TabWindowController)]] = [:]

        for (id, wc) in tabWindows {
            guard id != openTabID,   // the open tab rides beside its drawer; managed there
                  wc.isShown,
                  let screen = wc.currentScreen,
                  let number = screenNumber(screen),
                  let tab = store.tab(id: id) else { continue }
            groups[Key(screen: number, edge: tab.anchor.edge), default: []].append((id, wc))
        }

        for (key, entries) in groups where entries.count > 1 {
            // Leading first (front): top on a vertical edge, left on a horizontal one;
            // the id breaks ties (level tabs) so the order is stable.
            let ordered = entries.sorted { a, b in
                EdgeLayout.isFrontmost(a.wc.restingFrame, b.wc.restingFrame, edge: key.edge)
                    ?? (a.id.uuidString < b.id.uuidString)
            }
            // Tuck each tab just below the previous one, so the leading tab stays on top.
            for i in 1..<ordered.count {
                ordered[i].wc.order(below: ordered[i - 1].wc.windowNumber)
            }
        }
    }

    private func screenNumber(_ screen: NSScreen) -> Int? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
    }

    private func refreshOpenDrawer() {
        guard let id = openTabID,
              let wc = tabWindows[id],
              let tab = store.tab(id: id),
              let screen = wc.currentScreen else { return }
        drawer.refresh(tab: tab, tabFrame: wc.restingFrame, edge: tab.anchor.edge, on: screen)
        wc.applyFrame(EdgeLayout.openedTabFrame(edge: tab.anchor.edge,
                                                restingTabFrame: wc.restingFrame,
                                                drawerFrame: drawer.openFrame))
        updateFolderWatch()   // the open tab may have changed folder/sort
        updateSpotlightWatch()   // re-issue the Spotlight lookup for a Fresh / system-Recents tab
    }

    private func makeWindow(for tab: Tab) -> TabWindowController {
        let wc = TabWindowController(tab: tab, preferences: preferences)
        let id = tab.id
        wc.onTap = { [weak self] in self?.toggleDrawer(id) }
        wc.onHoverChanged = { [weak self] inside in self?.handleHover(id, inside: inside) }
        wc.onDropURLs = { [weak self] urls in self?.handleTabPillDrop(urls, toTab: id) }
        wc.model.onDragHover = { [weak self] targeted in self?.handleDragHover(id, targeted: targeted) }
        wc.onDragWillBegin = { [weak self] in self?.beginDrag(id) }
        wc.onDragChanged = { [weak self] in self?.previewDrag(id) }
        wc.onDragEnded = { [weak self] in self?.endDrag(id) }
        wc.model.onRequestSettings = { [weak self] in self?.onOpenSettings?(id) }
        wc.model.onDelete = { [weak self] in self?.store.removeTab(id: id) }
        wc.model.onMoveToEdge = { [weak self] edge in self?.moveTab(id, toEdge: edge) }
        return wc
    }

    /// Re-anchors a tab to a different edge (pill context menu), keeping its display
    /// and fractional position but **re-stacking it on top** of whatever already lives
    /// on the destination edge — so the de-overlap pass snaps the arriving tab into the
    /// nearest legal gap and leaves the tabs already there put (like a drag or a new
    /// tab), rather than carrying a low order that would shove them aside.
    private func moveTab(_ id: UUID, toEdge edge: Edge) {
        guard let tab = store.tab(id: id), tab.anchor.edge != edge else { return }
        var anchor = tab.anchor
        anchor.edge = edge
        anchor.order = topOrder(onEdge: edge, display: anchor.displayUUID, excluding: id)
        store.setAnchor(anchor, forTab: id)
    }

    // MARK: Drawer open / close

    /// Toggles a tab's drawer from outside its pill — the status-item menu's tab
    /// list. The same path a pill click takes.
    func toggle(tabID: UUID) {
        toggleDrawer(tabID)
    }

    private func toggleDrawer(_ id: UUID) {
        if openTabID == id { closeDrawer() } else { openDrawer(id) }
    }

    private func openDrawer(_ id: UUID) {
        guard let wc = tabWindows[id],
              let tab = store.tab(id: id),
              // Resolve the tab's screen *live* rather than trusting a possibly-stale
              // `currentScreen`: a parked tab (its display disconnected, default policy)
              // keeps its old screen reference, so a hotkey/spring-open must not slide a
              // drawer out onto a detached display. See ANALYSIS.md B3.
              let screen = resolvedScreen(for: tab) else { return }
        drawerInteractionGeneration &+= 1
        if let prev = openTabID, prev != id {
            tabWindows[prev]?.setOpen(false)
            tabWindows[prev]?.restoreResting()
        }
        cancelHoverClose()
        cancelReConceal(id)
        cancelSpringOpen()
        openTabID = id
        drawerSessionID = UUID()
        activeLaunchRequestID = nil
        restackTabs()   // re-seat the resting tabs (esp. a just-closed previous tab) below the new open one
        wc.reveal(duration: 0)   // restore a concealed (slid-off / sliver) tab to full size before opening
        wc.setOpen(true)
        refreshConcealment(animated: false)   // a drawer is open → suspend the edge-hover monitor
        let duration = animationDuration
        // The drawer slides out flush against the screen edge (centered on the
        // tab's resting position); the tab slides onto the drawer's inner face.
        drawer.show(tab: tab, tabFrame: wc.restingFrame, edge: tab.anchor.edge, on: screen, duration: duration)
        let openedTab = EdgeLayout.openedTabFrame(edge: tab.anchor.edge,
                                                  restingTabFrame: wc.restingFrame,
                                                  drawerFrame: drawer.openFrame)
        wc.animate(to: openedTab, duration: duration)
        startMonitoring()
        updateFolderWatch()   // live-refresh a folder tab while its drawer is open
        updateSpotlightWatch()   // gather Fresh / system-Recents items via Spotlight
    }

    private func closeDrawer() {
        cancelHoverClose()
        cancelSpringOpen()
        if openTabID != nil { drawerInteractionGeneration &+= 1 }
        let duration = animationDuration
        if let id = openTabID, let wc = tabWindows[id] {
            wc.setOpen(false)
            wc.animate(to: wc.restingFrame, duration: duration)   // slide the tab back to the edge
        }
        openTabID = nil
        drawerSessionID = nil
        activeLaunchRequestID = nil
        restackTabs()   // the tab rejoins its edge stack → restore the predictable z-order
        drawer.hide(duration: duration)
        stopMonitoring()
        stopFolderWatch()
        stopSpotlightWatch()
        refreshConcealment(animated: true)   // drawer closed → resume auto-hide/fade
    }

    /// The screen a tab should currently appear on: its anchored display if present,
    /// or the main display under the move-to-main policy, otherwise `nil` (parked).
    /// Mirrors the placement decision in `reconcile`, so a drawer only opens where
    /// the tab is actually shown.
    private func resolvedScreen(for tab: Tab) -> NSScreen? {
        if let screen = registry.screen(for: tab.anchor.displayUUID) { return screen }
        if preferences.disconnectPolicy == .moveToMain { return DisplayRegistry.primaryScreen }
        return nil
    }

    /// Drawer open/close animation duration; 0 when *Reduce Motion* is on.
    private var animationDuration: TimeInterval {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return 0 }
        return max(0, preferences.animationMs / 1000.0)
    }

    // MARK: Effective behavior

    /// A tab's behavior with the hover / auto-hide fields it doesn't override filled
    /// in from the global defaults (`Preferences.newTabOpenOnHover` / `newTabAutoHide`).
    /// Read live at interaction time, so changing a global default takes effect on the
    /// next hover / click-outside without touching any stored tab. See ANALYSIS.md I3.
    private func effectiveBehavior(_ tab: Tab) -> TabBehavior {
        tab.behavior.resolved(openOnHoverDefault: preferences.newTabOpenOnHover,
                              autoHideDefault: preferences.newTabAutoHide)
    }

    // MARK: Hover (hover-to-open tabs)

    private func handleHover(_ id: UUID, inside: Bool) {
        guard let tab = store.tab(id: id), effectiveBehavior(tab).openOnHover else { return }
        if inside {
            cancelHoverClose()
            // Already open: the pill rides the open drawer's inner face, so the
            // cursor re-entering it fires onHover(true) constantly. Re-running
            // openDrawer would replay the whole show — wiping an active
            // type-to-find filter, flipping a notes tab back to preview, and
            // restarting the open animation from alpha 0. (handleDragHover has
            // the same guard.)
            guard openTabID != id else { return }
            openDrawer(id)
        } else {
            scheduleHoverClose()
        }
    }

    private func scheduleHoverClose() {
        pendingHoverClose?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.closeDrawer() }
        pendingHoverClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func cancelHoverClose() {
        pendingHoverClose?.cancel()
        pendingHoverClose = nil
    }

    // MARK: Auto-hide / auto-fade (Dock-style concealment)

    /// Tabs eligible for concealment right now: on screen, with a concealment style,
    /// not the open tab, and not being dragged.
    private func concealableTabs() -> [(id: UUID, wc: TabWindowController)] {
        tabWindows.compactMap { id, wc in
            guard wc.isShown, wc.concealmentStyle != .never,
                  id != openTabID, id != draggingTabID, store.tab(id: id) != nil else { return nil }
            return (id, wc)
        }
    }

    /// Re-evaluates concealment for every concealable tab against the current cursor
    /// and starts/stops the edge-hover monitor. While a drawer is open, concealment
    /// is suspended entirely (the monitor is torn down). `animated` is false for the
    /// instant snap on reconcile/launch and true for live transitions.
    private func refreshConcealment(animated: Bool) {
        guard openTabID == nil else { stopRevealMonitoring(); return }
        let tabs = concealableTabs()
        guard !tabs.isEmpty else { stopRevealMonitoring(); return }
        startRevealMonitoring()
        evaluateConcealment(tabs, animated: animated)
    }

    /// Reveals or conceals every concealable tab for the current cursor. With
    /// `revealAllConcealedTogether` on, hovering *any* tab's reveal zone reveals them
    /// all (and they re-hide together once the cursor leaves every zone); otherwise
    /// each tab follows only its own zone. The shared core of the reconcile snap and
    /// the live mouse-moved monitor.
    private func evaluateConcealment(_ tabs: [(id: UUID, wc: TabWindowController)], animated: Bool) {
        let mouse = NSEvent.mouseLocation
        // While a file is being dragged near a concealed tab, pre-reveal it from a
        // more generous "peek" zone so spring-loading has a full pill to aim at.
        let peeking = fileBeingDragged()
        func zone(_ wc: TabWindowController) -> CGRect { peeking ? peekZone(for: wc) : revealZone(for: wc) }
        let revealAll = preferences.revealAllConcealedTogether
            && tabs.contains { zone($0.wc).contains(mouse) }
        for (id, wc) in tabs {
            let reveal = revealAll || zone(wc).contains(mouse)
            applyRevealState(id: id, wc: wc, reveal: reveal, animated: animated)
        }
    }

    /// The wider region whose hover reveals a concealed tab while a file drag is in
    /// flight (the drag-over "peek").
    private func peekZone(for wc: TabWindowController) -> CGRect {
        wc.restingFrame.insetBy(dx: -Self.peekSlop, dy: -Self.peekSlop)
    }

    /// Whether a file drag is currently in progress — gates the drag-over peek.
    /// A real drag session writes the drag pasteboard *after* the mouse-down, so a
    /// file drag is: left button down, AND the drag pasteboard's `changeCount` has
    /// advanced past the value stamped at the press. The pasteboard *retaining* the
    /// previous drag's files proves nothing — without the stamp, any window drag or
    /// text selection after the session's first file drag false-positived the peek.
    /// The (out-of-process) content read happens once per drag session, cached by
    /// `changeCount`, not once per mouse-moved event.
    private func fileBeingDragged() -> Bool {
        guard NSEvent.pressedMouseButtons & 0x1 != 0 else { return false }
        let pasteboard = NSPasteboard(name: .drag)
        let count = pasteboard.changeCount
        guard count != dragPasteboardCountAtPress else { return false }
        if let cached = dragPasteboardCanReadFiles, cached.count == count { return cached.canRead }
        let canRead = pasteboard.canReadObject(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true])
        dragPasteboardCanReadFiles = (count, canRead)
        return canRead
    }

    /// Stamps the drag pasteboard's `changeCount` at a mouse-down, so a subsequent
    /// drag counts as a *file* drag only if the pasteboard was rewritten after the
    /// press (i.e. a real drag session started).
    private func stampDragPasteboardAtPress() {
        dragPasteboardCountAtPress = NSPasteboard(name: .drag).changeCount
    }

    /// Applies one tab's reveal decision: reveal it, or — when it should hide —
    /// schedule the delayed re-conceal (animated pass) or snap it hidden at once.
    private func applyRevealState(id: UUID, wc: TabWindowController, reveal: Bool, animated: Bool) {
        let duration = animated ? animationDuration : 0
        if reveal {
            cancelReConceal(id)
            wc.reveal(duration: duration)
        } else if wc.isConcealed {
            cancelReConceal(id)   // already hidden — nothing to schedule
        } else if animated {
            scheduleReConceal(id)
        } else {
            cancelReConceal(id)
            wc.conceal(duration: 0)
        }
    }

    /// The screen region whose hover reveals a concealed tab.
    private func revealZone(for wc: TabWindowController) -> CGRect {
        wc.restingFrame.insetBy(dx: -Self.revealSlop, dy: -Self.revealSlop)
    }

    /// Whether the current cursor location warrants `wc` staying revealed: it's in the
    /// tab's own reveal zone, or — with `revealAllConcealedTogether` — in any
    /// concealable tab's zone. Used to gate the delayed re-conceal so grouped tabs
    /// stay out while the cursor is over any of them.
    private func cursorReveals(_ wc: TabWindowController) -> Bool {
        let mouse = NSEvent.mouseLocation
        if revealZone(for: wc).contains(mouse) { return true }
        guard preferences.revealAllConcealedTogether else { return false }
        return concealableTabs().contains { revealZone(for: $0.wc).contains(mouse) }
    }

    private func scheduleReConceal(_ id: UUID) {
        guard pendingReConceal[id] == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingReConceal[id] = nil
            guard id != self.openTabID, id != self.draggingTabID, let wc = self.tabWindows[id] else { return }
            // Only conceal if the cursor still doesn't warrant revealing this tab — its
            // own zone, or (with "reveal all together") any concealable tab's zone.
            if !self.cursorReveals(wc) {
                wc.conceal(duration: self.animationDuration)
            }
        }
        pendingReConceal[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reConcealDelay, execute: work)
    }

    private func cancelReConceal(_ id: UUID) {
        pendingReConceal[id]?.cancel()
        pendingReConceal[id] = nil
    }

    private func handleRevealMouseMoved() {
        evaluateConcealment(concealableTabs(), animated: true)
    }

    private func startRevealMonitoring() {
        // Mouse-moved monitors need no permission (unlike key monitors / event taps).
        if revealMonitorGlobal == nil {
            // `.leftMouseDragged` (in addition to `.mouseMoved`) so a file drag from
            // Finder toward a concealed tab triggers the peek even though the cursor
            // isn't "moving" in the plain sense while the button is held.
            // `.leftMouseDown` stamps the drag pasteboard's changeCount at the press,
            // which is what lets `fileBeingDragged` tell a real file drag apart from
            // a window drag over the previous drag's leftover pasteboard.
            revealMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] event in
                if event.type == .leftMouseDown {
                    self?.stampDragPasteboardAtPress()
                } else {
                    self?.handleRevealMouseMoved()
                }
            }
        }
        if revealMonitorLocal == nil {
            revealMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
                if event.type == .leftMouseDown {
                    self?.stampDragPasteboardAtPress()
                } else {
                    self?.handleRevealMouseMoved()
                }
                return event
            }
        }
    }

    private func stopRevealMonitoring() {
        if let m = revealMonitorGlobal { NSEvent.removeMonitor(m); revealMonitorGlobal = nil }
        if let m = revealMonitorLocal { NSEvent.removeMonitor(m); revealMonitorLocal = nil }
        pendingReConceal.values.forEach { $0.cancel() }
        pendingReConceal.removeAll()
    }

    // MARK: Drag-to-reposition (snap-to-edge preview)

    private func beginDrag(_ id: UUID) {
        closeDrawer()
        draggingTabID = id
        lastSnapGuide = nil
        cancelReConceal(id)
        tabWindows[id]?.reveal(duration: 0)   // a slid-off / faded tab becomes fully grabbable
        dragLocked = store.tab(id: id)?.locked ?? false
        if let wc = tabWindows[id] { dragLength = wc.contentLength }
    }

    /// Live preview while dragging: the pill stays attached to the nearest edge and
    /// slides along it to the cursor — but **snapped into the nearest legal gap**
    /// among the tabs already on that edge, so you see exactly where it will land and
    /// the tabs already there never move. Reshapes as it crosses to a new edge. A
    /// locked tab doesn't move.
    private func previewDrag(_ id: UUID) {
        guard !dragLocked, let wc = tabWindows[id], let target = dragTarget() else { return }
        // Fire the alignment haptic the moment the pill magnetizes to a new guide.
        let guide = magnetized(target, excluding: id).guide
        if guide != lastSnapGuide {
            if guide != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
            }
            lastSnapGuide = guide
        }
        let frame = snappedDragFrame(id, wc: wc, target: target)
        wc.previewSnap(toFrame: frame, edge: target.edge, on: target.screen)
    }

    /// The drag target's position magnetized to the quarter guides (0/¼/½/¾/1) and to
    /// neighboring tabs' positions, plus the guide it locked onto (`nil` = free) for
    /// haptic timing.
    private func magnetized(_ target: (screen: NSScreen, edge: Edge, position: Double),
                            excluding id: UUID) -> (position: Double, guide: Double?) {
        let vf = target.screen.visibleFrame
        let neighbors = restingFrames(onEdge: target.edge, screen: target.screen, excluding: id).map {
            EdgeLayout.position(forPoint: CGPoint(x: $0.midX, y: $0.midY), edge: target.edge, in: vf)
        }
        let snap = EdgeLayout.snappedPosition(target.position, guides: EdgeLayout.snapGuides + neighbors)
        return (snap.position, snap.snappedGuide)
    }

    /// Commit the **snapped** position on release — the same legal slot the preview
    /// showed — so the pill stays exactly where it appeared rather than jumping. A
    /// locked tab doesn't move.
    private func endDrag(_ id: UUID) {
        draggingTabID = nil
        lastSnapGuide = nil
        defer { refreshConcealment(animated: true) }   // re-arm auto-hide/fade for the dropped tab
        guard !dragLocked else { return }
        guard let wc = tabWindows[id], let target = dragTarget(),
              let uuid = registry.uuid(for: target.screen) else {
            // Couldn't resolve a drop target (e.g. released over no known display):
            // snap the pill back to its stored resting frame instead of leaving it
            // stranded at the preview position until an unrelated reconcile.
            reconcile()
            return
        }
        let snapped = snappedDragFrame(id, wc: wc, target: target)
        let position = EdgeLayout.position(forPoint: CGPoint(x: snapped.midX, y: snapped.midY),
                                           edge: target.edge, in: target.screen.visibleFrame)
        // Stack the dropped tab on top of whatever shares its (new) edge, so the
        // de-overlap pass treats it as the newcomer that yields — though it already
        // sits in a legal slot, so nothing actually has to move.
        let order = topOrder(onEdge: target.edge, display: uuid, excluding: id)
        store.setAnchor(ScreenAnchor(displayUUID: uuid, edge: target.edge, position: position, order: order), forTab: id)
    }

    /// The dragged pill's frame snapped into the nearest legal gap among the other
    /// tabs sharing the target edge/screen — the slot it shows mid-drag and keeps on
    /// release. The other tabs are taken at their current resting frames and left
    /// untouched.
    private func snappedDragFrame(_ id: UUID, wc: TabWindowController,
                                  target: (screen: NSScreen, edge: Edge, position: Double)) -> CGRect {
        let position = magnetized(target, excluding: id).position
        let tentative = wc.dragFrame(edge: target.edge, position: position,
                                     length: dragLength, on: target.screen)
        let others = restingFrames(onEdge: target.edge, screen: target.screen, excluding: id)
        return EdgeLayout.snappedAlongEdge(incoming: tentative, fixed: others, edge: target.edge,
                                           gap: EdgeLayout.minTabGap, in: target.screen.visibleFrame)
    }

    /// The resting frames of the shown tabs on `edge`/`screen`, excluding `id` — the
    /// fixed obstacles a dragged or re-placed tab snaps around.
    private func restingFrames(onEdge edge: Edge, screen: NSScreen, excluding id: UUID) -> [CGRect] {
        guard let number = screenNumber(screen) else { return [] }
        return tabWindows.compactMap { tid, wc in
            guard tid != id, wc.isShown,
                  let s = wc.currentScreen, screenNumber(s) == number,
                  store.tab(id: tid)?.anchor.edge == edge else { return nil }
            return wc.restingFrame
        }
    }

    /// One past the highest `order` among the tabs sharing `edge` on `display`
    /// (ignoring `excluding`) — the stacking slot for a freshly placed tab, so the
    /// de-overlap pass treats it as the newcomer that yields.
    private func topOrder(onEdge edge: Edge, display uuid: String, excluding id: UUID? = nil) -> Int {
        let orders = store.tabs
            .filter { $0.id != id && $0.anchor.edge == edge && $0.anchor.displayUUID == uuid }
            .map(\.anchor.order)
        return PersistedLayoutBounds.nextOrder(after: orders.max())
    }

    /// The screen / edge / position the dragged pill should snap to, from the
    /// current global cursor location.
    private func dragTarget() -> (screen: NSScreen, edge: Edge, position: Double)? {
        let mouse = NSEvent.mouseLocation
        guard let screen = screenContaining(mouse) else { return nil }
        let visible = screen.visibleFrame
        let edge = nearestEdge(to: mouse, in: visible)
        let position = EdgeLayout.position(forPoint: mouse, edge: edge, in: visible)
        return (screen, edge, position)
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.min { squaredDistance($0.frame, point) < squaredDistance($1.frame, point) }
    }

    private func nearestEdge(to p: CGPoint, in vf: CGRect) -> Edge {
        let distances: [(Edge, CGFloat)] = [
            (.left, abs(p.x - vf.minX)),
            (.right, abs(vf.maxX - p.x)),
            (.top, abs(vf.maxY - p.y)),
            (.bottom, abs(p.y - vf.minY)),
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .right
    }

    private func squaredDistance(_ rect: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = p.x - rect.midX, dy = p.y - rect.midY
        return dx * dx + dy * dy
    }

    // MARK: File drops & spring-loading

    private func handleTabPillDrop(_ urls: [URL], toTab id: UUID) {
        guard let tab = store.tab(id: id) else { return }
        let accepted = tab.kind == .items ? urls : urls.filter(\.isFileURL)
        handleFileDrop(accepted, slot: -1, toTab: id)
    }

    /// Routes files **and web links** dropped on a tab/drawer. `slot` is the drawer
    /// slot they landed on (or -1 for the tab pill / drawer background): dropping on
    /// an **app** opens them with it, on a **folder** files the files into it,
    /// otherwise they are added (items tab) or filed into the mirrored directory
    /// (folder tab). Web links can't be moved on disk, so they're only *added* (and
    /// only on an items tab); they can still be opened-with an app.
    private func handleFileDrop(_ urls: [URL], slot: Int, toTab id: UUID) {
        guard !urls.isEmpty, let tab = store.tab(id: id) else { return }
        let fileURLs = urls.filter { $0.isFileURL }
        // Resolve what the drop landed on. A slot drop can only come from the open
        // drawer, so resolve the target against the items it is *showing*
        // (`drawer.model.items`) rather than a fresh re-list: the directory may have
        // changed since the drawer rendered, and a re-listed target can differ from
        // the slot the user aimed at (a re-list also costs a directory enumeration
        // per drop). The pill path (slot == -1) has no target to resolve at all.
        let target: DrawerItem?
        if slot >= 0 {
            let liveItems: [DrawerItem]
            if tab.kind == .folder {
                liveItems = openTabID == id ? drawer.model.items : FolderLister.contents(of: tab)
            } else {
                liveItems = tab.items
            }
            target = liveItems.first { $0.slot == slot }
        } else {
            target = nil
        }

        if let target, target.kind == .application {
            ItemLauncher.open(urls, withApp: target)   // files *or* links → open-with
            return
        }
        if let target, target.kind == .trash {
            if FileMover.trash(urls) {   // drop onto Trash → move the files to the Trash
                // The classic "poof" where the files vanished into the Trash.
                NSAnimationEffect.poof.show(centeredAt: NSEvent.mouseLocation,
                                            size: NSSize(width: 32, height: 32), completionHandler: {})
            }
            drawer.model.iconNonce += 1   // the Trash now has something — re-resolve its icon to "full"
            if tab.kind == .folder { refreshOpenDrawer() }
            return
        }
        if let target, target.kind == .folder, let directory = BookmarkResolver.url(for: target) {
            moveFilesWithUndo(fileURLs, into: directory)   // only files can be filed in
            if tab.kind == .folder { refreshOpenDrawer() }
            return
        }

        switch tab.kind {
        case .notes, .disks, .network, .cloud, .recents, .fresh:
            return   // notes take no drops; the live listings (Disks/Network/Cloud/Recents/Fresh) are read-only
        case .folder:
            guard let directory = FolderLister.resolveFolder(tab) else { return }
            moveFilesWithUndo(fileURLs, into: directory)
            if openTabID == id { refreshOpenDrawer() } else { openDrawer(id) }
        case .items:
            let dropped = urls.map { DrawerItem.fromDroppedURL($0) }   // files & links, in drop order
            // Add each (dedup) and collect the id actually in the tab — the existing
            // item on a duplicate, or the new one — preserving order, de-duped.
            var ids: [UUID] = []
            for newItem in dropped {
                if let itemID = store.addItem(newItem, toTab: id), !ids.contains(itemID) {
                    ids.append(itemID)
                }
            }
            if slot >= 0 {
                // Land them in a run from the target slot (so a duplicate moves there
                // too, and a multi-file drop doesn't scatter). See ANALYSIS.md I4.
                store.placeItems(ids, startingAt: slot, inTab: id)
            }
            if openTabID != id { openDrawer(id) }   // a store change already refreshed an open drawer
        }
    }

    /// Spring-loads a tab: hovering it with a file drag opens its drawer after a
    /// short delay, so the file can be dropped onto the drawer's contents.
    private func handleDragHover(_ id: UUID, targeted: Bool) {
        guard targeted else { cancelSpringOpen(for: id); return }
        guard openTabID != id else { return }
        cancelSpringOpen()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSpringOpen = nil
            self?.pendingSpringOpenTabID = nil
            // A soft tick as the spring finally releases — the sibling of the
            // drag-snap alignment haptic, marking "the drawer is opening under you".
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            self?.openDrawer(id)
        }
        pendingSpringOpen = work
        pendingSpringOpenTabID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func cancelSpringOpen(for id: UUID? = nil) {
        guard id == nil || pendingSpringOpenTabID == id else { return }
        pendingSpringOpen?.cancel()
        pendingSpringOpen = nil
        pendingSpringOpenTabID = nil
    }

    // MARK: Hotkeys

    private func registerHotkeyIfNeeded(for tab: Tab) {
        guard let spec = tab.hotkey,
              KeyCodes.isUsableHotkey(keyCode: spec.keyCode, modifiers: spec.carbonModifiers) else {
            unregisterHotkey(tab.id)
            return
        }
        if let existing = hotkeys[tab.id], existing.spec == spec { return }
        // Already tried and failed this exact spec — don't retry/re-log until it changes.
        if failedHotkeySpecs[tab.id] == spec { return }
        unregisterHotkey(tab.id)

        let hotkey = CarbonHotkey(identifier: hotkeyCounter)
        hotkeyCounter += 1
        let id = tab.id
        hotkey.onPressed = { [weak self] in self?.toggleDrawer(id) }
        if hotkey.register(keyCode: spec.keyCode, modifiers: spec.carbonModifiers) {
            hotkeys[tab.id] = (hotkey, spec)
            failedHotkeySpecs[tab.id] = nil
        } else {
            failedHotkeySpecs[tab.id] = spec
        }
    }

    private func unregisterHotkey(_ id: UUID) {
        hotkeys[id]?.hotkey.unregister()
        hotkeys[id] = nil
        failedHotkeySpecs[id] = nil
    }

    // MARK: Drawer wiring & launching

    private func wireDrawer() {
        drawer.model.onLaunch = { [weak self] item in self?.launch(item) }
        drawer.model.onRemoveItem = { [weak self] item in
            guard let self, let id = self.openTabID else { return }
            // The classic poof, same as drop-on-Trash — physical feedback that the
            // item left the grid (only the launcher entry goes; the file stays put).
            NSAnimationEffect.poof.show(centeredAt: NSEvent.mouseLocation,
                                        size: NSSize(width: 32, height: 32), completionHandler: {})
            self.store.removeItem(id: item.id, fromTab: id)
        }
        drawer.model.onRevealItem = { item in ItemLauncher.revealInFinder(item) }
        drawer.model.onEmptyTrash = { [weak self] in self?.emptyTrash() }
        drawer.model.onRenameItem = { [weak self] item in self?.renameItem(item) }
        drawer.model.onChangeItemIcon = { [weak self] item in self?.changeItemIcon(item) }
        drawer.model.onResetItemIcon = { [weak self] item in self?.resetItemIcon(item) }
        drawer.model.onCustomizeItemIcon = { [weak self] item in self?.customizeIcon(item) }
        drawer.model.onEjectItem = { [weak self] item in self?.ejectDisk(item) }
        drawer.model.onEjectAll = { [weak self] in self?.ejectAllDisks() }
        drawer.model.onDropFiles = { [weak self] urls, slot in
            guard let self, let id = self.openTabID else { return }
            self.handleFileDrop(urls, slot: slot, toTab: id)
        }
        drawer.model.onMouseEntered = { [weak self] in self?.cancelHoverClose() }
        drawer.model.onMouseExited = { [weak self] in
            guard let self, let id = self.openTabID, let tab = self.store.tab(id: id) else { return }
            if self.effectiveBehavior(tab).openOnHover { self.scheduleHoverClose() }
        }
        drawer.model.onPlaceItem = { [weak self] itemID, slot in
            guard let self, let id = self.openTabID else { return }
            self.store.placeItem(itemID, atSlot: slot, inTab: id)
        }
        drawer.model.onGroupItems = { [weak self] draggedID, targetID in
            guard let self, let id = self.openTabID else { return }
            self.store.groupItems(draggedID: draggedID, ontoTargetID: targetID, inTab: id)
        }
        drawer.model.onPlaceInGroup = { [weak self] itemID, slot in
            guard let self, let id = self.openTabID,
                  let groupID = self.drawer.model.openGroupID else { return }
            self.store.placeItemInGroup(itemID, atSlot: slot, groupID: groupID, inTab: id)
        }
        drawer.model.onRemoveFromGroup = { [weak self] itemID, groupID in
            guard let self, let id = self.openTabID else { return }
            self.store.removeFromGroup(childID: itemID, groupID: groupID, inTab: id)
        }
        drawer.model.onRenameGroup = { [weak self] groupID, name in
            guard let self, let id = self.openTabID else { return }
            self.store.renameGroup(groupID: groupID, to: name, inTab: id)
        }
        drawer.model.onOpenSettings = { [weak self] in
            guard let self, let id = self.openTabID else { return }
            self.closeDrawer()
            self.onOpenSettings?(id)
        }
        drawer.model.onToggleLocked = { [weak self] in
            guard let self, let id = self.openTabID else { return }
            let locked = self.store.tab(id: id)?.locked ?? false
            self.store.setLocked(!locked, forTab: id)
        }
        drawer.model.onNotesChanged = { [weak self] text in
            guard let self, let id = self.openTabID else { return }
            self.store.setNotes(text, forTab: id)
        }
        drawer.model.onOpenFolder = { [weak self] in
            guard let self, let id = self.openTabID, let tab = self.store.tab(id: id),
                  let url = FolderLister.resolveFolder(tab) else { return }
            NSWorkspace.shared.open(url)
        }
        drawer.model.onClearRecents = { [weak self] in
            guard let self else { return }
            RecentsStore.shared.clear()
            if self.openTabID.flatMap({ self.store.tab(id: $0) })?.kind == .recents { self.refreshOpenDrawer() }
        }
    }

    private func launch(_ item: DrawerItem) {
        guard let tabID = openTabID, let sessionID = drawerSessionID else { return }
        let request = DrawerLaunchRequest(tabID: tabID, sessionID: sessionID)
        activeLaunchRequestID = request.requestID
        ItemLauncher.launch(item) { [weak self] result in
            guard let self else { return }
            let canUpdateDrawer = request.canUpdateDrawer(
                openTabID: self.openTabID,
                sessionID: self.drawerSessionID,
                requestID: self.activeLaunchRequestID
            )
            guard case let .success(url) = result else {
                if canUpdateDrawer { self.activeLaunchRequestID = nil }
                return
            }

            // Recents tracks confirmed opens, even when a newer launch or drawer
            // session has superseded the request that initiated this one.
            self.recordRecent(item, url: url)
            guard canUpdateDrawer else { return }
            self.activeLaunchRequestID = nil
            let tab = self.store.tab(id: request.tabID)
            if tab?.behavior.keepOpenAfterLaunch != true {
                self.closeDrawer()
            } else if tab?.kind == .recents {
                self.refreshOpenDrawer()   // re-list so the just-opened item jumps to the top
            }
        }
    }

    /// Records an opened target into the Recents history. Only the kinds you'd want to
    /// re-open are tracked (apps/files/folders/links/cloud); volumes and the Trash are
    /// skipped. `url` is the target whose launch was confirmed by `ItemLauncher`.
    private func recordRecent(_ item: DrawerItem, url: URL) {
        guard [.application, .file, .folder, .url, .cloud].contains(item.kind) else { return }
        RecentsStore.shared.record(RecentItem(url: url, kind: item.kind, name: item.displayName, date: Date()))
    }

    // MARK: Item rename / icon

    /// Floats a dialog above the drawer panel. The drawer rides at popup-menu level,
    /// so an app-modal alert left at its default level can end up *behind* a large
    /// drawer — invisible, while it blocks every click in the app.
    private func floatAboveDrawer(_ window: NSWindow) {
        window.level = NSWindow.Level(rawValue: preferences.tabWindowLevel.drawerWindowLevel.rawValue + 1)
    }

    /// Renames an item via a small modal prompt, then commits it to the store.
    private func renameItem(_ item: DrawerItem) {
        guard let id = openTabID else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Item"
        alert.informativeText = "Enter a new name for “\(item.displayName)”."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = item.displayName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)   // a text prompt needs key focus
        floatAboveDrawer(alert.window)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var updated = item
        updated.displayName = name
        store.updateItem(updated, inTab: id)
    }

    /// Lets the user pick an image to use as an item's icon, then stores it as a
    /// bookmark so it survives moves/renames.
    private func changeItemIcon(_ item: DrawerItem) {
        guard let id = openTabID else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image to use as this item's icon"

        NSApp.activate(ignoringOtherApps: true)
        floatAboveDrawer(panel)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setCustomIconBookmark(BookmarkResolver.makeBookmark(for: url),
                                    forItem: item.id, inTab: id)
    }

    /// Empties the Trash (Trash item context menu) after a confirmation, via Finder
    /// — the only way without Full Disk Access. The user is asked once to allow
    /// controlling Finder; declining (or cancelling) just leaves the Trash as-is.
    private func emptyTrash() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Empty the Trash?"
        // Say how many items are about to go, the way Finder does. (Shares the
        // metadata count's `.DS_Store` caveat — see TrashInspector.)
        let count = TrashInspector.trashCount()
        let what = count > 0 ? "the \(count) item\(count == 1 ? "" : "s")" : "the items"
        alert.informativeText = "This permanently erases \(what) in the Trash. You can’t undo this."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)   // a modal alert needs key focus
        floatAboveDrawer(alert.window)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if FileMover.emptyTrash() {
            drawer.model.iconNonce += 1   // re-resolve the Trash icon in place (full → empty)
        }
    }

    /// Clears an item's custom icon (image *and* generated style), restoring its default.
    private func resetItemIcon(_ item: DrawerItem) {
        guard let id = openTabID else { return }
        store.setIconStyle(nil, forItem: item.id, inTab: id)
    }

    /// Opens the generated-icon editor for `item` and stores the result. The drawer
    /// closes first because the editor is an ordinary window (the drawer floats above
    /// normal windows), then reopens when the editor closes unless another drawer has
    /// since opened. A persistent `.items` item keeps its saved style on the item (and
    /// clears any image override); a live item's style is stored on the tab, keyed by
    /// its path.
    private func customizeIcon(_ item: DrawerItem) {
        guard let id = openTabID, let kind = store.tab(id: id)?.kind else { return }
        let sessionID = UUID()
        let drawerGenerationBeforeEditor = drawerInteractionGeneration
        let expectedDrawerGeneration = drawerGenerationBeforeEditor &+ 1
        iconEditorSessionID = sessionID
        closeDrawer()   // the one generation change this editor session expects
        iconEditor.show(
            itemName: item.displayName,
            initial: item.iconStyle,
            onSave: { [weak self] style in
                guard let self, self.iconEditorSessionID == sessionID else { return }
                if kind == .items {
                    self.store.setIconStyle(style, forItem: item.id, inTab: id)
                } else if let path = item.url?.path {
                    self.store.setIconStyle(style, forItemPath: path, inTab: id)
                }
            },
            onClose: { [weak self] in
                guard let self, self.iconEditorSessionID == sessionID else { return }
                self.iconEditorSessionID = nil
                // A tab opened while the editor was up is now the user's active
                // context, even if it later closed; only our intentional close is allowed.
                guard self.drawerInteractionGeneration == expectedDrawerGeneration,
                      self.openTabID == nil,
                      self.store.tab(id: id) != nil else { return }
                self.openDrawer(id)
            }
        )
    }

    // MARK: Disks (eject)

    /// Whether the open tab shows a live volume listing — the **Disks** tab or a
    /// **Network** tab (whose network shares are ejectable `.disk` items too). Both
    /// must refresh when volumes mount, unmount, rename, or are ejected.
    private var openTabReflectsVolumes: Bool {
        guard let kind = openTabID.flatMap({ store.tab(id: $0) })?.kind else { return false }
        return kind == .disks || kind == .network
    }

    /// Ejects a disk item's volume and refreshes the open Disks/Network drawer so the
    /// volume drops out of the listing at once (the unmount notification is a
    /// belt-and-suspenders refresh if the eject completes asynchronously).
    private func ejectDisk(_ item: DrawerItem) {
        DiskEjector.eject(item)
        if openTabReflectsVolumes {
            refreshOpenDrawer()
        }
    }

    /// Ejects every ejectable volume in the open Disks drawer, showing a per-item
    /// spinner while each unmount runs off the main thread (the call blocks), then
    /// refreshes the listing once they've all completed.
    private func ejectAllDisks() {
        let items = drawer.model.items
        guard !items.isEmpty else { return }
        drawer.model.ejectingItemIDs = Set(items.map(\.id))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for item in items { DiskEjector.eject(item) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.drawer.model.ejectingItemIDs = []
                if self.openTabReflectsVolumes { self.refreshOpenDrawer() }
            }
        }
    }

    /// Moves dropped files into `directory`, then shows an Undo toast in the drawer
    /// header that can move them back. A no-op (no toast) if nothing actually moved.
    private func moveFilesWithUndo(_ urls: [URL], into directory: URL) {
        let result = FileMover.movingFiles(urls, into: directory)
        guard !result.moves.isEmpty else { return }
        let moves = result.moves
        let n = moves.count
        let name = directory.lastPathComponent
        showUndoToast("Moved \(n) item\(n == 1 ? "" : "s") to \(name)") { [weak self] in
            FileMover.undo(moves)
            self?.refreshOpenDrawer()
        }
    }

    /// Shows a transient Undo toast in the open drawer's header, auto-dismissed after
    /// a few seconds (cancelling any previous one).
    private func showUndoToast(_ message: String, action: @escaping () -> Void) {
        undoToastClearItem?.cancel()
        drawer.setUndoToast(DrawerUndo(message: message, action: action))
        let clear = DispatchWorkItem { [weak self] in self?.drawer.setUndoToast(nil) }
        undoToastClearItem = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: clear)
    }

    /// Watches for volumes mounting, unmounting, or being renamed so an open
    /// Disks/Network drawer stays in sync with the live set. (A closed drawer
    /// re-lists when it next opens, so only the open one needs refreshing.)
    private func startVolumeMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification,
                     NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.openTabReflectsVolumes else { return }
                self.refreshOpenDrawer()
            }
            volumeObservers.append(token)
        }
    }

    private func stopVolumeMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        volumeObservers.forEach { center.removeObserver($0) }
        volumeObservers.removeAll()
    }

    // MARK: Folder live-refresh (FSEvents)

    /// Watches the open folder tab's directory (via a `DispatchSource` on its fd) and
    /// re-lists the drawer when its contents change — so a folder tab updates live,
    /// not only when re-opened. Watches one directory at a time (the open tab's).
    private func updateFolderWatch() {
        guard let id = openTabID, let tab = store.tab(id: id), tab.kind == .folder,
              let url = FolderLister.resolveFolder(tab) else { stopFolderWatch(); return }
        startFolderWatch(url)
    }

    private func startFolderWatch(_ url: URL) {
        if folderWatchPath == url.path { return }   // already watching this directory
        stopFolderWatch()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleFolderRefresh() }
        source.setCancelHandler { close(fd) }
        folderWatch = source
        folderWatchPath = url.path
        source.resume()
    }

    private func stopFolderWatch() {
        folderWatch?.cancel()   // its cancel handler closes the fd
        folderWatch = nil
        folderWatchPath = nil
        pendingFolderRefresh?.cancel()
        pendingFolderRefresh = nil
    }

    /// Keeps the Fresh "just landed" pill dot in sync. While any Fresh tab exists a
    /// 60 s timer re-checks, so the dot lights within a minute of a file arriving and
    /// fades on its own once it's older than `freshRecentWindow`. The check runs only
    /// when the timer is first armed and on its beats — **not** on every reconcile,
    /// which used to mean one landing-zone sweep per store mutation.
    private func updateFreshBadgeTimer() {
        guard store.tabs.contains(where: { $0.kind == .fresh }) else {
            freshBadgeTimer?.invalidate()
            freshBadgeTimer = nil
            freshBadgeSpotlight.cancel()
            return
        }
        guard freshBadgeTimer == nil else { return }   // armed — the timer drives the re-checks
        refreshFreshBadges()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshFreshBadges()
        }
        timer.tolerance = 10   // a badge dot doesn't need punctual wakeups
        freshBadgeTimer = timer
    }

    /// Lights every Fresh tab pill's dot when the newest item in the (shared) Fresh
    /// scopes landed within `freshRecentWindow`. Asks **Spotlight** (index-only, so it
    /// can never trigger a folder-access prompt — unlike a direct directory scan, see
    /// fable-is-awesome.md FB1); one lookup covers all Fresh tabs.
    private func refreshFreshBadges() {
        let freshTabIDs = store.tabs.filter { $0.kind == .fresh }.map(\.id)
        guard !freshTabIDs.isEmpty else { return }
        let now = Date()
        freshBadgeSpotlight.start(mode: .dateAdded, scopes: FreshLister.scopes(),
                                  limit: FreshLister.limit) { [weak self] results in
            guard let self else { return }
            let recent = results.contains { now.timeIntervalSince($0.date) <= Self.freshRecentWindow }
            for id in freshTabIDs { self.tabWindows[id]?.model.hasRecentArrival = recent }
        }
    }

    /// Watches the home Trash (its fd, via a `DispatchSource`) and bumps the drawer's
    /// icon nonce when it changes, so an open Trash item flips full↔empty and its
    /// count badge updates the instant Finder empties it or something is trashed.
    private func startTrashWatch() {
        guard trashWatch == nil,
              let trash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: false) else { return }
        let fd = open(trash.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleTrashRefresh() }
        source.setCancelHandler { close(fd) }
        trashWatch = source
        source.resume()
    }

    /// Coalesces a burst of Trash directory events (a batch delete streams many)
    /// into one icon-nonce bump — the same debounce the folder watch uses. Every
    /// bump re-runs item icon resolution, so raw event streams were re-resolving
    /// the whole open drawer once per trashed file. Skipped while the drawer is
    /// hidden: `hide()` clears the items and every reopen rebuilds the cells (and
    /// re-resolves their icons) anyway.
    private func scheduleTrashRefresh() {
        pendingTrashRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.drawer.isVisible else { return }
            self.drawer.model.iconNonce += 1
        }
        pendingTrashRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Coalesces a burst of directory-change events into a single re-list.
    private func scheduleFolderRefresh() {
        pendingFolderRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let id = self.openTabID, self.store.tab(id: id)?.kind == .folder else { return }
            self.refreshOpenDrawer()
        }
        pendingFolderRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    // MARK: Spotlight live-refresh (Fresh tab & system Recents source)

    /// Starts (or restarts) the Spotlight lookup backing the open drawer when it's a
    /// **Fresh** tab or a **Recents** tab whose source includes the system; otherwise
    /// stops any running query. Results fill the drawer asynchronously via
    /// `applySpotlightItems`. The async sibling of `updateFolderWatch`.
    private func updateSpotlightWatch() {
        guard let id = openTabID, let tab = store.tab(id: id) else { stopSpotlightWatch(); return }
        // A reconcile that didn't change the open tab must not cancel-and-restart a
        // gather that's still running for it — a burst of mutations (e.g. per-keystroke
        // tab edits) would otherwise starve the query so results never land.
        let restartable = !(spotlightWatchTabID == id && spotlight.isGathering)
        switch tab.kind {
        case .fresh:
            // Spotlight-only: reading the index can never trigger a folder-access
            // (TCC) prompt, unlike a direct scan of ~/Downloads & co. — the reason
            // the FreshScanner path was retired from the live app (FB1).
            guard restartable else { return }
            spotlightWatchTabID = id
            spotlight.start(mode: .dateAdded, scopes: FreshLister.scopes(), limit: FreshLister.limit) { [weak self] results in
                self?.applySpotlightItems(FreshLister.items(from: results), forTab: id)
            }
        case .recents where tab.recentsSource.includesSystem:
            guard restartable else { return }
            spotlightWatchTabID = id
            let includeMacDring = tab.recentsSource.includesMacDring
            let home = FileManager.default.homeDirectoryForCurrentUser
            spotlight.start(mode: .lastUsed, scopes: [home], limit: RecentsStore.limit) { [weak self] results in
                let system = results.map { RecentItem(spotlight: $0) }
                let history = includeMacDring ? RecentsStore.shared.items : []
                let merged = RecentsStore.deduplicatedByURL(history + system, limit: RecentsStore.limit)
                self?.applySpotlightItems(RecentsLister.items(from: merged), forTab: id)
            }
        default:
            stopSpotlightWatch()
        }
    }

    private func stopSpotlightWatch() {
        spotlight.cancel()
        spotlightWatchTabID = nil
    }

    /// Applies an async live listing to the open drawer — only if the same tab is
    /// still open — re-applying its per-target icon overrides and re-seating the
    /// riding tab onto the (possibly resized) drawer.
    private func applySpotlightItems(_ items: [DrawerItem], forTab id: UUID) {
        guard openTabID == id, let wc = tabWindows[id], let tab = store.tab(id: id) else { return }
        drawer.updateLiveItems(items.applyingIconStyles(from: tab.iconStyles))
        wc.applyFrame(EdgeLayout.openedTabFrame(edge: tab.anchor.edge,
                                                restingTabFrame: wc.restingFrame,
                                                drawerFrame: drawer.openFrame))
    }

    // MARK: Running-app indicator

    /// Tracks the set of running apps' bundle IDs so application items show a live
    /// "running" dot, updating as apps launch and quit.
    private func startRunningAppMonitoring() {
        refreshRunningApps()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshRunningApps()
            }
            runningAppObservers.append(token)
        }
    }

    private func refreshRunningApps() {
        drawer.model.runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private func stopRunningAppMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        runningAppObservers.forEach { center.removeObserver($0) }
        runningAppObservers.removeAll()
    }

    // MARK: Dismissal monitoring

    private func startMonitoring() {
        stopMonitoring()
        // Mouse-down in another app closes the drawer (unless the tab is pinned).
        // Global *mouse* monitors need no permission; we only watch keys locally.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let id = self.openTabID, let tab = self.store.tab(id: id) else {
                    self.closeDrawer()
                    return
                }
                if self.effectiveBehavior(tab).autoHide { self.closeDrawer() }
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            // Don't steal keys while a modal is up (the rename / Empty-Trash alerts, an
            // open panel) — they own their own text field and Esc/Return — or from one
            // of the app's ordinary titled windows (Settings / New Tab). The borderless
            // drawer/tab panels are neither modal nor `.titled`.
            if NSApp.modalWindow != nil { return event }
            if let key = NSApp.keyWindow, key.styleMask.contains(.titled) { return event }
            return self.handleDrawerKey(event)
        }
    }

    /// Routes a key for the open drawer: Esc closes (or clears an active filter first);
    /// while **type-to-find** is active, Up/Down move the result selection and Return
    /// launches it. Character input goes to the focused filter field directly — the
    /// monitor only swallows the navigation keys. Returns `nil` to swallow a handled
    /// key, else the event passes on.
    private func handleDrawerKey(_ event: NSEvent) -> NSEvent? {
        let model = drawer.model
        // While an input method is composing marked text (CJK, accent pickers, etc.),
        // Return and arrows belong to the text system, not drawer result navigation.
        if (NSApp.keyWindow?.firstResponder as? NSTextInputClient)?.hasMarkedText() == true {
            return event
        }
        // The filter field (a focused text field) handles character input and Delete
        // itself; the monitor only swallows the keys that drive result navigation so
        // they don't move the text cursor instead.
        switch event.keyCode {
        case 53:   // Esc — clear a filter, else leave an open group, else close the drawer
            if model.isSearching {
                model.clearSearch()
            } else if model.openGroupID != nil {
                model.openGroupID = nil
            } else {
                closeDrawer()
            }
            return nil
        case 125, 126:   // Down, Up — move the result selection while filtering
            guard model.isSearching else { return event }
            model.moveSelection(down: event.keyCode == 125)
            return nil
        case 36, 76:   // Return, Enter — launch the selected result
            guard model.isSearching else { return event }
            model.launchSelection()
            return nil
        default:
            return event
        }
    }

    private func stopMonitoring() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }

    // MARK: Lifecycle

    /// Persists immediately and tears down all windows/hotkeys (called on quit).
    func saveAndTeardown() {
        store.saveNow()
        stopMonitoring()
        stopRevealMonitoring()
        stopVolumeMonitoring()
        stopFolderWatch()
        stopRunningAppMonitoring()
        freshBadgeTimer?.invalidate()
        freshBadgeTimer = nil
        freshBadgeSpotlight.cancel()
        stopSpotlightWatch()
        drawer.hide(duration: 0)     // instant on quit, no animation
        openTabID = nil
        drawerSessionID = nil
        activeLaunchRequestID = nil
        for (_, wc) in tabWindows { wc.close() }
        tabWindows.removeAll()
        for (_, entry) in hotkeys { entry.hotkey.unregister() }
        hotkeys.removeAll()
    }
}
