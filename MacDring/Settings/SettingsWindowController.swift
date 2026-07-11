import AppKit
import SwiftUI

/// Hosts the SwiftUI `SettingsView` in a standard titled window. Switches the
/// app to a regular (Dock-visible) app while open so the window can take focus,
/// then back to `.accessory` when it closes.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let preferences: Preferences
    private let store: TabStore
    private let registry: DisplayRegistry
    private let updateChecker: UpdateChecker
    private let router = SettingsRouter()

    init(preferences: Preferences, store: TabStore, registry: DisplayRegistry, updateChecker: UpdateChecker) {
        self.preferences = preferences
        self.store = store
        self.registry = registry
        self.updateChecker = updateChecker
    }

    /// Shows Settings. If `selectTab` is given, opens straight to the Tabs pane
    /// with that tab selected.
    func show(selectTab: UUID? = nil) {
        if let selectTab { router.showTab(selectTab) }

        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(preferences: preferences, store: store, registry: registry, router: router, updateChecker: updateChecker)
            )
            hosting.sizingOptions = [.minSize]

            let window = NSWindow(contentViewController: hosting)
            window.title = "Top Drawer Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 580, height: 540))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("MacDringSettingsWindow")
            self.window = window
        }

        NSApp.setActivationPolicy(.regular)
        // Defer activation a tick. When invoked from a tab's context menu, the
        // action fires inside the menu's tracking run loop and a synchronous
        // activate()/makeKeyAndOrderFront() doesn't bring the window forward (the
        // "Configure Tab does nothing the first time" bug). `ignoringOtherApps` +
        // `orderFrontRegardless` force it forward from a background agent.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            NSApp.activate(ignoringOtherApps: true)
            // makeKeyAndOrderFront/orderFrontRegardless don't restore a
            // miniaturized window — re-opening Settings would appear to do
            // nothing while the window sits minimized.
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Only drop back to the menu-bar agent policy if no other ordinary window
        // (e.g. an open New Tab dialog) still needs the app to be `.regular`.
        NSApp.revertToAccessoryIfNoOrdinaryWindows(excluding: window)
    }
}
