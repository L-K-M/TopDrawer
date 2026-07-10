import AppKit
import SwiftUI

/// Presents the small "New Tab" modal and creates the configured tab. A fresh
/// window is built each time so the dialog starts clean at the chosen type.
final class NewTabWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let preferences: Preferences
    private let store: TabStore
    private let registry: DisplayRegistry

    init(preferences: Preferences, store: TabStore, registry: DisplayRegistry) {
        self.preferences = preferences
        self.store = store
        self.registry = registry
    }

    func show(kind: TabKind) {
        window?.close()

        let view = NewTabView(
            kind: kind,
            defaultColorHex: preferences.defaultTabColorHex,
            onCreate: { [weak self] config in self?.create(config) },
            onCancel: { [weak self] in self?.window?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "New Tab"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func create(_ config: NewTabConfig) {
        defer { window?.close() }
        guard let uuid = registry.mainScreenUUID() else { return }

        // Stagger new right-edge tabs so they don't land exactly on top of each other,
        // and stack each on top of the existing ones (highest `order`) so the
        // de-overlap pass snaps the *newcomer* into a legal gap and leaves the tabs
        // already there put.
        let rightTabs = store.tabs.filter { $0.anchor.edge == .right && $0.anchor.displayUUID == uuid }
        let position = max(0.12, min(0.88, 0.5 - 0.08 * Double(rightTabs.count)))
        let order = PersistedLayoutBounds.nextOrder(after: rightTabs.map(\.anchor.order).max())

        let glyph: TabGlyph
        switch config.kind {
        case .items: glyph = .symbol("square.grid.2x2.fill")
        case .notes: glyph = .symbol("note.text")
        case .folder: glyph = .symbol("folder.fill")
        case .disks: glyph = .symbol("externaldrive.fill")
        case .network: glyph = .symbol("externaldrive.connected.to.line.below.fill")
        case .cloud: glyph = .symbol("icloud.fill")
        case .recents: glyph = .symbol("clock.arrow.circlepath")
        case .fresh: glyph = .symbol("sparkles")
        }

        let tab = Tab(
            title: config.name,
            colorHex: config.colorHex,
            glyph: glyph,
            anchor: ScreenAnchor(displayUUID: uuid, edge: .right, position: position, order: order),
            behavior: preferences.newTabBehavior,
            gridColumns: Int(preferences.gridColumns),
            gridRows: Int(preferences.gridRows),
            kind: config.kind,
            layout: config.kind.defaultLayout,
            folderBookmark: config.folderBookmark,
            folderURL: config.folderURL
        )
        store.addTab(tab)
    }

    func windowWillClose(_ notification: Notification) {
        // Return to agent behavior only if no other ordinary window (e.g. Settings)
        // is still open. Shared with SettingsWindowController so both guard alike.
        NSApp.revertToAccessoryIfNoOrdinaryWindows(excluding: window)
    }
}
