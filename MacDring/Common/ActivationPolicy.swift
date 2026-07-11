import AppKit

extension NSApplication {
    /// Reverts Top Drawer to its menu-bar agent policy (`.accessory`, no Dock icon),
    /// **unless another ordinary window is still visible**.
    ///
    /// Top Drawer is an `.accessory` app; it switches to `.regular` while a titled
    /// window (Settings / New Tab) is open so that window can take focus, and each
    /// such window calls this when it closes. The guard — ignore the window that's
    /// closing (`excluding`) and stay `.regular` if any other titled, main-capable
    /// window remains — means closing one of those windows while another is still
    /// open no longer drops the Dock presence the open one needs. The borderless,
    /// non-activating tab/drawer panels can't become main, so they're never counted.
    /// See BACKLOG.md's legacy ID index (C2).
    func revertToAccessoryIfNoOrdinaryWindows(excluding window: NSWindow?) {
        // `isVisible` is false for a miniaturized window, but a minimized
        // Settings window still needs the app to stay `.regular` — dropping to
        // `.accessory` removes its Dock thumbnail and strands it off-screen.
        let otherOrdinaryWindowOpen = windows.contains {
            $0 != window && ($0.isVisible || $0.isMiniaturized) && $0.canBecomeMain
        }
        if !otherOrdinaryWindowOpen { setActivationPolicy(.accessory) }
    }
}
