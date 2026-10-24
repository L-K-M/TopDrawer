import AppKit

/// One click used to delete a tab and every item in it, instantly and
/// irreversibly. Both removal paths — the strip's context menu and
/// Settings → Tabs — funnel through this single gate: a tab that still
/// holds items gets a confirmation naming the loss; an empty tab just goes.
enum TabRemoval {
    /// Ask before destroying a tab that has items. Returns true when removal
    /// should proceed (user confirmed, or the tab was empty anyway).
    @MainActor
    static func confirm(_ tab: Tab) -> Bool {
        let count = tab.items.flattenedLaunchable().count
        guard count > 0 else { return true }

        let alert = NSAlert()
        alert.messageText = "Remove “\(tab.title)”?"
        alert.informativeText = "This deletes the tab and its \(count) item\(count == 1 ? "" : "s"). This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove Tab")
        alert.addButton(withTitle: "Cancel")
        // The app is an accessory: a strip context menu can pop this modal while
        // another app is key — activate or the alert sits behind everything.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
