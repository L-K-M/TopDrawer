import AppKit
import PictKit

/// Top Drawer's side of the shared icon store.
///
/// Drawers are full of app icons, and on macOS 26 `NSWorkspace.icon(forFile:)`
/// hands back the squircle-masked composite for every one of them. Top Drawer draws
/// its own slots, so it is no more obliged to show that than Zap's switcher is —
/// and now that the store and the resolution ladder live in `PictKit`, it doesn't
/// have to implement any of it either.
///
/// Deliberately small, and a mirror of Jetty's `JettyIcons`: Top Drawer has no
/// icon-size slider, no ingestion and no search UI, so there is nothing here but
/// the options a drawer wants, a watcher, and a way to ask whether Pict is around.
final class TopDrawerIcons {

    static let shared = TopDrawerIcons()

    let store: IconStore
    /// Thread-safe by construction — `IconResolver` guards its cache with a lock and
    /// does its work on its own queue — so this type carries no actor isolation and
    /// `icon(for:)` is callable from wherever an icon is needed, including the
    /// static resolution helpers that draw a slot.
    let resolver: IconResolver

    /// Called when what an open drawer is drawing has stopped being current, so it
    /// can re-list. Set by `TabController`, which owns the open drawer.
    ///
    /// Fires for two reasons, which is why it is named for the effect rather than
    /// the cause: another app wrote to the store, or a re-render finished and there
    /// is now artwork to read that there wasn't a moment ago. Without the second, an
    /// icon set in Pict would reach a *closed* drawer only — the re-list would run
    /// while the resolver was still empty and draw the system icon.
    var onIconsInvalidated: (() -> Void)?

    private var watcher: IconStoreWatcher?
    private var screenObserver: NSObjectProtocol?

    private init(store: IconStore = IconStore()) {
        self.store = store
        // A drawer slot sits in a grid, so `bleed: 0`: free-form artwork spilling
        // past its cell is the look Zap's switcher is after and the wrong one here,
        // where slots are laid out on a fixed pitch and the neighbour is close. No
        // baked shadow either — the drawer already has its own material behind it.
        self.resolver = IconResolver(options: .plain(pointSize: Self.slotPointSize,
                                                     scale: Self.backingScale()),
                                     store: store)
        watch()
        watchScreens()

        // The other half of the store watcher — see `onIconsInvalidated`. Also what
        // carries a display change through: `watchScreens` re-renders at the new
        // scale, and this is what tells an open drawer the sharper artwork is there.
        resolver.onIconsResolved = { [weak self] in self?.onIconsInvalidated?() }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// The largest a slot icon is drawn. One cache size rather than tracking a
    /// setting, because Top Drawer has none — slot size comes from `DrawerMetrics`.
    private static let slotPointSize: Double = 64

    private static func backingScale() -> CGFloat {
        NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    /// The icon to draw for `target`, or `nil` to fall back to what the system says.
    /// A dictionary lookup; a miss warms in the background and returns `nil`, so
    /// nothing here can block a drawer opening.
    func icon(for target: IconTarget) -> NSImage? {
        resolver.icon(for: target)
    }

    /// How the shared store knows a drawer item.
    ///
    /// `nil` for the kinds that are not a thing on disk — the Trash, a group, a
    /// broken bookmark — which have nothing for another app to agree with. Disks,
    /// network shares and cloud folders *are* paths, and keying them here is what
    /// lets a custom icon for a specific share survive a re-list in every app rather
    /// than only in the tab that set it.
    static func target(for item: DrawerItem) -> IconTarget? {
        guard let url = BookmarkResolver.url(for: item) else { return nil }
        // Exhaustive on purpose — no `default`. A new `ItemKind` should be a compile
        // error here, not silently enrolled in a store three other apps read.
        switch item.kind {
        case .application:
            return .application(bundleURL: url, bundleIdentifier: Bundle(url: url)?.bundleIdentifier)
        case .url:
            return .link(url)
        case .file, .folder, .disk, .cloud:
            return .file(url)
        case .trash, .group:
            return nil
        }
    }

    private func watch() {
        watcher = IconStoreWatcher(store: store) { [weak self] in
            // Both, and in this order. `invalidate()` schedules the re-render; the
            // hook re-lists now, which matters for an icon the user *removed* — that
            // resolves to the system icon, lands no artwork, and so would never reach
            // `onIconsResolved` to be corrected later.
            self?.resolver.invalidate()
            self?.onIconsInvalidated?()
        }
        watcher?.start()
    }

    /// Plugging in a sharper display makes every cached icon too soft for it, and
    /// nothing else here would notice.
    ///
    /// No `invalidate()` after the update: `IconResolver.update(_:)` compares the
    /// options and invalidates itself when they differ, so an irrelevant display
    /// change costs a comparison and a real one re-renders exactly once. Calling
    /// `invalidate()` here as well would drop the cache and re-warm it twice.
    private func watchScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.resolver.update(.plain(pointSize: Self.slotPointSize,
                                         scale: Self.backingScale()))
        }
    }
}
