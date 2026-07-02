import AppKit
import SwiftUI

/// An `NSHostingView` that accepts the first mouse click even when its panel
/// isn't key, so a click on the (background-app) pill registers immediately.
private final class FirstMouseTabHostingView: NSHostingView<TabStripView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hosts a borderless, non-activating panel for one tab pill: keeps it sized to
/// its SwiftUI content, anchored to its edge, and relays click/hover/drag/drop
/// up to the `TabController`. Non-activating so clicking a tab never steals
/// focus from the user's frontmost app.
final class TabWindowController {

    let tabID: UUID
    let model: TabStripModel

    private let preferences: Preferences
    private let panel: NSPanel
    private let hostingView: FirstMouseTabHostingView

    /// The screen the pill is currently placed on (used to position the drawer).
    private(set) var currentScreen: NSScreen?
    /// The pill's flush-to-edge resting frame (where it sits when its drawer is
    /// closed). The drawer is centered along the edge on this frame.
    private(set) var restingFrame: CGRect = .zero
    private var anchor: ScreenAnchor

    /// The tab's idle concealment style (Dock-style auto-hide / auto-fade). The
    /// `TabController` drives *when* to conceal/reveal; this controller owns *how*.
    var concealmentStyle: TabConcealment = .never
    /// Whether the tab is currently concealed (slid off / shrunk / faded). The
    /// controller flips this through `conceal`/`reveal`; placement honors it so a
    /// reconcile doesn't pop a hidden tab back onto the edge.
    private(set) var isConcealed = false
    /// Whether the tab is currently shrunk to an edge sliver (the shared-edge
    /// auto-hide case). The window is smaller than the pill here, so we snap in/out
    /// of this state rather than animate (the clipped content doesn't slide cleanly).
    private var isSliverHidden = false

    /// The frame we last set deliberately. If the panel's frame diverges from this
    /// while we're not the one changing it, an external agent (a window-management
    /// / tiling tool) grabbed it — so we snap it back. See `defendFrame`.
    private var intendedFrame: CGRect = .zero
    /// Number of in-flight frame animations. A *count* (not a bool) so overlapping
    /// animations — a rapid open/close/switch — don't let the first one's completion
    /// re-arm the frame-defender while a later one is still running. See ANALYSIS.md B8.
    private var frameAdjustmentDepth = 0
    private var frameObservers: [NSObjectProtocol] = []

    // Controller hooks.
    var onTap: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDropURLs: (([URL]) -> Void)?
    var onDragWillBegin: (() -> Void)?
    var onDragChanged: (() -> Void)?
    var onDragEnded: (() -> Void)?

    init(tab: Tab, preferences: Preferences) {
        self.tabID = tab.id
        self.preferences = preferences
        self.anchor = tab.anchor
        self.model = TabStripModel(title: tab.title, colorHex: tab.colorHex, glyph: tab.glyph,
                                   edge: tab.anchor.edge, acceptsWebURLDrops: tab.kind == .items)

        let hosting = FirstMouseTabHostingView(rootView: TabStripView(model: model, preferences: preferences))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        self.hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
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
        panel.isMovable = false   // we position it programmatically; deter window drags
        panel.minSize = .zero     // allow shrinking to a thin auto-hide sliver
        panel.level = preferences.tabWindowLevel.nsWindowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let container = NSView(frame: panel.frame)
        container.autoresizesSubviews = true
        // Clip to the window so the auto-hide sliver shows only the pill's clean
        // edge strip; the full-size hosting view behind it is cropped to the sliver.
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        hosting.frame = container.bounds
        container.addSubview(hosting)
        panel.contentView = container
        self.panel = panel

        wireModelCallbacks()
        observeExternalFrameChanges()
    }

    deinit {
        frameObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Watch for frame changes we didn't make (e.g. a tiling tool resizing the
    /// pill) and restore the intended frame, so a tab can't be "lost."
    private func observeExternalFrameChanges() {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let token = center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                self?.defendFrame()
            }
            frameObservers.append(token)
        }
    }

    private func defendFrame() {
        guard frameAdjustmentDepth == 0, intendedFrame != .zero else { return }
        let current = panel.frame
        let drifted = abs(current.minX - intendedFrame.minX) > 1
            || abs(current.minY - intendedFrame.minY) > 1
            || abs(current.width - intendedFrame.width) > 1
            || abs(current.height - intendedFrame.height) > 1
        guard drifted else { return }
        panel.setFrame(intendedFrame, display: true)   // matches intended now → no further restore
    }

    private func wireModelCallbacks() {
        model.onTap = { [weak self] in self?.onTap?() }
        model.onHoverChanged = { [weak self] inside in self?.onHoverChanged?(inside) }
        model.onDropURLs = { [weak self] urls in self?.onDropURLs?(urls) }
        model.onDragBegan = { [weak self] in self?.onDragWillBegin?() }
        model.onDragChanged = { [weak self] in self?.onDragChanged?() }
        model.onDragEnded = { [weak self] in self?.onDragEnded?() }
    }

    /// The pill's current on-screen frame.
    var frame: CGRect { panel.frame }

    /// The panel's window number, used to set a relative z-order among overlapping
    /// tabs that share an edge.
    var windowNumber: Int { panel.windowNumber }

    /// Orders this pill's panel directly **below** the panel with `windowNumber`, so
    /// overlapping tabs on an edge draw in a predictable front-to-back order.
    func order(below windowNumber: Int) {
        panel.order(.below, relativeTo: windowNumber)
    }

    /// The along-edge extent of the pill (its length), used to keep a consistent
    /// size while previewing a snap to a different edge during a drag.
    var contentLength: CGFloat { max(restingFrame.width, restingFrame.height) }

    func update(tab: Tab) {
        anchor = tab.anchor
        // Equality-guard each @Published write: update(tab:) runs for every tab on
        // every reconcile, and an unguarded assignment emits objectWillChange even
        // for an identical value — five spurious pill invalidations per tab per
        // store mutation.
        if model.title != tab.title { model.title = tab.title }
        if model.colorHex != tab.colorHex { model.colorHex = tab.colorHex }
        if model.glyph != tab.glyph { model.glyph = tab.glyph }
        if model.edge != tab.anchor.edge { model.edge = tab.anchor.edge }
        let acceptsWebURLDrops = tab.kind == .items
        if model.acceptsWebURLDrops != acceptsWebURLDrops { model.acceptsWebURLDrops = acceptsWebURLDrops }

        // On a concealment-style change, re-seed the concealed flag: a concealable
        // style starts concealed (so the next `place` doesn't flash it onto the edge
        // before the controller re-evaluates the cursor), and `.never` reveals.
        // `place`/the controller then apply the matching presentation.
        if tab.behavior.concealment != concealmentStyle {
            concealmentStyle = tab.behavior.concealment
            isConcealed = concealmentStyle != .never
        }
    }

    func setOpen(_ open: Bool) {
        model.isOpen = open
        // An open tab is always fully visible, riding the drawer face; closing it
        // returns it to its resting frame, so it's no longer concealed either way.
        // The controller re-evaluates concealment once the drawer is closed.
        isConcealed = false
        if open { setAlpha(1, duration: 0) }
    }

    /// Measures the pill content and computes its flush-to-edge resting frame on
    /// `screen`. Moves the panel there unless its drawer is open (in which case
    /// the controller positions it on the drawer's inner face).
    func place(on screen: NSScreen) {
        currentScreen = screen
        panel.level = preferences.tabWindowLevel.nsWindowLevel

        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let thickness = CGFloat(preferences.tabThickness) * preferences.tabStyle.thicknessScale
        let size: CGSize
        if preferences.tabStyle == .classic {
            // Classic hugs its content along the thin (perpendicular) axis for a
            // compact folder-tab look; the along-edge axis keeps a thickness floor
            // so a short-label tab stays easy to click. Matches the view, which
            // drops its thin-axis frame for classic.
            size = model.edge.isVertical
                ? CGSize(width: fitting.width, height: max(fitting.height, thickness))
                : CGSize(width: max(fitting.width, thickness), height: fitting.height)
        } else {
            size = model.edge.isVertical
                ? CGSize(width: thickness, height: max(fitting.height, thickness))
                : CGSize(width: max(fitting.width, thickness), height: thickness)
        }

        restingFrame = EdgeLayout.tabFrame(edge: model.edge, position: anchor.position, size: size, in: screen.visibleFrame)
        applyConcealmentPresentation(duration: 0)
    }

    /// Positions the panel at an explicit frame (e.g. the open position, riding on
    /// the drawer's inner face).
    func applyFrame(_ frame: CGRect) {
        intendedFrame = frame
        panel.setFrame(frame, display: true)
        hostingView.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
    }

    /// Returns the pill to its flush-to-edge resting position.
    func restoreResting() { applyFrame(restingFrame) }

    /// Overrides the flush-to-edge resting frame (used by the de-overlap layout
    /// pass for tabs that share an edge), moving the pill there unless its drawer
    /// is currently open — in which case the new resting frame takes effect when
    /// the drawer closes and the tab slides back to the edge.
    func setRestingFrame(_ frame: CGRect) {
        restingFrame = frame
        applyConcealmentPresentation(duration: 0)
    }

    // MARK: Auto-hide / auto-fade

    /// Conceals the tab (slide off the edge for `.hide`, dim for `.fade`). No-op
    /// when the tab has no concealment style or its drawer is open.
    func conceal(duration: TimeInterval) {
        guard concealmentStyle != .never, !model.isOpen else { return }
        isConcealed = true
        applyConcealmentPresentation(duration: duration)
    }

    /// Reveals a concealed tab (slide back to its edge / un-dim).
    func reveal(duration: TimeInterval) {
        guard isConcealed else { return }
        isConcealed = false
        applyConcealmentPresentation(duration: duration)
    }

    /// Applies the current `(isConcealed, concealmentStyle)` as the pill's alpha
    /// and frame. The frame is only touched while the drawer is closed — when open
    /// the controller positions the pill on the drawer's inner face. An open tab is
    /// always fully opaque.
    private func applyConcealmentPresentation(duration: TimeInterval) {
        var targetAlpha: CGFloat = 1
        var target = restingFrame
        var sliver = false

        if isConcealed && !model.isOpen {
            switch concealmentStyle {
            case .never:
                break
            case .fade:
                targetAlpha = CGFloat(preferences.fadedOpacity)
            case .hide:
                if let screen = currentScreen {
                    // Sliding off an edge shared with another display would land the
                    // pill on the neighbor instead of off-screen — so on a shared
                    // edge, shrink to a sliver on our own screen (a true hide, not a
                    // fade). Otherwise slide the whole pill off. See EdgeLayout.
                    let others = NSScreen.screens.filter { $0.frame != screen.frame }.map(\.frame)
                    if EdgeLayout.hiddenFrameSpillsOntoOtherScreens(edge: model.edge, restingTabFrame: restingFrame,
                                                                    screenVisibleFrame: screen.visibleFrame,
                                                                    otherScreenFrames: others) {
                        target = EdgeLayout.sliverTabFrame(edge: model.edge, restingTabFrame: restingFrame)
                        sliver = true
                    } else {
                        target = EdgeLayout.hiddenTabFrame(edge: model.edge, restingTabFrame: restingFrame, in: screen.visibleFrame)
                    }
                }
            }
        }

        setAlpha(targetAlpha, duration: duration)
        guard !model.isOpen else { return }
        // The sliver window is smaller than the pill, so snap into and out of it
        // (a frame animation would distort the clipped content); slide-off and fade
        // animate normally.
        let instant = sliver || isSliverHidden
        isSliverHidden = sliver
        if sliver {
            applySliverFrame(target)
        } else if instant || duration <= 0 {
            applyFrame(target)
        } else {
            animate(to: target, duration: duration)
        }
    }

    /// Shows the tab as a thin edge sliver while keeping the hosting view at the
    /// full pill size — shifted so the window exposes only the clean edge strip
    /// (within the tab's padding), never the centered glyph/label cropped into it.
    private func applySliverFrame(_ sliverFrame: CGRect) {
        intendedFrame = sliverFrame
        panel.setFrame(sliverFrame, display: false)
        hostingView.frame = CGRect(x: restingFrame.minX - sliverFrame.minX,
                                   y: restingFrame.minY - sliverFrame.minY,
                                   width: restingFrame.width,
                                   height: restingFrame.height)
        panel.display()
    }

    /// Sets the panel's opacity, optionally animated.
    private func setAlpha(_ alpha: CGFloat, duration: TimeInterval) {
        guard duration > 0 else { panel.alphaValue = alpha; return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }

    /// Whether the pill is currently on screen (vs. parked because its display is
    /// disconnected). Used to scope the de-overlap pass to visible tabs.
    var isShown: Bool { panel.isVisible }

    /// Animates the pill to `frame` over `duration` seconds (0 = instant). Used to
    /// slide the tab onto / off the drawer's inner face in sync with the drawer.
    func animate(to frame: CGRect, duration: TimeInterval) {
        guard duration > 0 else { applyFrame(frame); return }
        intendedFrame = frame
        frameAdjustmentDepth += 1   // suppress the frame-defender during the animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.frameAdjustmentDepth = max(0, self.frameAdjustmentDepth - 1)
            // Only re-sync the hosting view once the last overlapping animation ends.
            if self.frameAdjustmentDepth == 0 {
                self.hostingView.frame = self.panel.contentView?.bounds ?? .zero
            }
        })
    }

    /// The flush-to-edge frame this pill would occupy mid-drag at fractional
    /// `position` on `edge`/`screen`, sized to keep a consistent `length` along the
    /// edge (and the pill's thickness across it). The controller snaps this against
    /// the other tabs before showing it, so the inputs are exposed without the pill
    /// committing to them.
    func dragFrame(edge: Edge, position: Double, length: CGFloat, on screen: NSScreen) -> CGRect {
        let thickness = CGFloat(preferences.tabThickness) * preferences.tabStyle.thicknessScale
        let size: CGSize = edge.isVertical
            ? CGSize(width: thickness, height: max(length, thickness))
            : CGSize(width: max(length, thickness), height: thickness)
        return EdgeLayout.tabFrame(edge: edge, position: position, size: size, in: screen.visibleFrame)
    }

    /// Live drag preview: shows the pill at an explicit (already snapped) `frame` on
    /// `edge`/`screen`. Updates `model.edge` so the pill reshapes (corners face
    /// inward) as it crosses edges.
    func previewSnap(toFrame frame: CGRect, edge: Edge, on screen: NSScreen) {
        currentScreen = screen
        model.edge = edge
        restingFrame = frame
        applyFrame(frame)
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}
