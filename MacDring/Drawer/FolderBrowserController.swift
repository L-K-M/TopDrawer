import AppKit
import SwiftUI

final class FolderBrowserController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var model = FolderBrowserModel()
    var isShown: Bool { popover.isShown }

    func show(_ item: DrawerItem, relativeTo rect: NSRect, of view: NSView,
              onLaunch: @escaping (DrawerItem) -> Void,
              onReveal: @escaping (DrawerItem) -> Void,
              onPreview: @escaping (DrawerItem) -> Void) {
        close()
        model = FolderBrowserModel()
        popover.delegate = self
        popover.behavior = .semitransient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: FolderBrowserView(
            folder: item, model: model, onLaunch: onLaunch, onReveal: onReveal, onPreview: onPreview))
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
    }

    func contains(_ window: NSWindow?) -> Bool {
        guard let window, popover.isShown else { return false }
        return popover.contentViewController?.view.window === window
    }

    func close() {
        popover.animates = false
        popover.performClose(nil)
        model.cancel()
        popover.contentViewController = nil
    }

    func popoverDidClose(_ notification: Notification) {
        guard !popover.isShown else { return }
        model.cancel()
        popover.contentViewController = nil
    }
}
