import AppKit

/// One click used to delete a tab and every item in it, instantly and
/// irreversibly. Both removal paths — the strip's context menu and
/// Settings → Tabs — funnel through this single gate: a tab that still
/// holds items gets a confirmation naming the loss; an empty tab just goes.
enum TabRemoval {
    /// Asks before destroying a tab that has items. Returns true when removal
    /// should proceed (the user confirmed, or the tab was empty anyway).
    ///
    /// `present` runs the alert and returns its response. The default activates
    /// Top Drawer first: the app is an accessory, so a prompt raised while another
    /// app is active would otherwise sit behind it.
    static func confirm(_ tab: Tab,
                        present: (NSAlert) -> NSApplication.ModalResponse = { alert in
                            NSApp.activate(ignoringOtherApps: true)
                            return alert.runModal()
                        }) -> Bool {
        let count = tab.items.flattenedLaunchable().count
        guard count > 0 else { return true }

        let alert = NSAlert()
        alert.messageText = "Remove “\(tab.title)”?"
        alert.informativeText = "This deletes the tab and its \(count) item\(count == 1 ? "" : "s"). This can't be undone."
        alert.alertStyle = .warning
        let remove = alert.addButton(withTitle: "Remove Tab")
        // Return must not destroy items: removing takes a deliberate click, and
        // Escape still cancels (NSAlert gives it to the button titled Cancel).
        remove.keyEquivalent = ""
        remove.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return present(alert) == .alertFirstButtonReturn
    }
}
