import AppKit
import SwiftUI

final class FolderBrowserController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var model = FolderBrowserModel()
    private var hasSession = false
    private enum CloseReason { case dismissed, replaced }
    var onClose: (() -> Void)?
    var isShown: Bool { popover.isShown }

    func show(_ item: DrawerItem, relativeTo rect: NSRect, of view: NSView,
              preferredEdge: NSRectEdge = .maxX,
              onLaunch: @escaping (DrawerItem) -> Void,
              onReveal: @escaping (DrawerItem) -> Void,
              onPreview: @escaping (DrawerItem) -> Void) {
        dismiss(reason: .replaced)
        model = FolderBrowserModel()
        popover.delegate = self
        popover.behavior = .semitransient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: FolderBrowserView(
            folder: item, model: model, onLaunch: onLaunch, onReveal: onReveal, onPreview: onPreview))
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
        hasSession = popover.isShown
    }

    /// The popover edge that opens **inward** from a drawer on `edge`: a left-edge
    /// drawer grows rightward, so its popovers open on the item's right; a right-edge
    /// drawer grows leftward, so they open on the left; top/bottom drawers open
    /// below/above. Pointing outward (the old fixed `.maxX`) pushed right-edge
    /// popovers off the drawer and let top/bottom ones detach.
    static func preferredPopoverEdge(for edge: Edge) -> NSRectEdge {
        switch edge {
        case .left:   return .maxX
        case .right:  return .minX
        case .top:    return .minY
        case .bottom: return .maxY
        }
    }

    func contains(_ window: NSWindow?) -> Bool {
        guard let window, popover.isShown else { return false }
        return popover.contentViewController?.view.window === window
    }

    func close() {
        dismiss(reason: .dismissed)
    }

    private func dismiss(reason: CloseReason) {
        popover.delegate = nil
        popover.animates = false
        popover.performClose(nil)
        finishClose(reason: reason)
    }

    private func finishClose(reason: CloseReason) {
        let shouldNotify = hasSession && reason == .dismissed
        hasSession = false
        model.cancel()
        popover.contentViewController = nil
        if shouldNotify { onClose?() }
    }

    func popoverDidClose(_ notification: Notification) {
        guard !popover.isShown else { return }
        finishClose(reason: .dismissed)
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }
}
