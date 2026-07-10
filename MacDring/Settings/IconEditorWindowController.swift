import AppKit
import SwiftUI

/// Presents the generated-icon editor (`IconEditorView`) for a drawer item in a
/// small modal-style window and reports the chosen `IconStyle` (or `nil` to clear)
/// back to the caller. A fresh window is built each time so it opens clean.
///
/// Like the New Tab / Settings windows, it switches the app to `.regular` while open
/// so the window can take focus, then reverts via the shared activation-policy guard
/// when it closes.
final class IconEditorWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var sessions: [ObjectIdentifier: Session] = [:]

    private struct Session {
        let id: UUID
        let onClose: () -> Void
    }

    /// Shows the editor for `itemName`, seeded with `initial`. `onSave` is called with
    /// the chosen style (or `nil` for "use default") when the user saves. `onClose`
    /// fires exactly once after Save, Cancel, or a title-bar close.
    func show(itemName: String, initial: IconStyle?,
              onSave: @escaping (IconStyle?) -> Void,
              onClose: @escaping () -> Void) {
        window?.close()

        let sessionID = UUID()
        let view = IconEditorView(
            itemName: itemName,
            initial: initial,
            onSave: { [weak self] style in
                guard self?.isCurrentSession(sessionID) == true else { return }
                onSave(style)
                self?.closeSession(sessionID)
            },
            onCancel: { [weak self] in self?.closeSession(sessionID) }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Customize Icon"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        sessions[ObjectIdentifier(window)] = Session(id: sessionID, onClose: onClose)
        self.window = window

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func isCurrentSession(_ id: UUID) -> Bool {
        guard let window, let session = sessions[ObjectIdentifier(window)] else { return false }
        return session.id == id
    }

    private func closeSession(_ id: UUID) {
        guard isCurrentSession(id) else { return }
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        let session = sessions.removeValue(forKey: ObjectIdentifier(closingWindow))
        if window === closingWindow { window = nil }
        NSApp.revertToAccessoryIfNoOrdinaryWindows(excluding: closingWindow)
        session?.onClose()
    }
}
