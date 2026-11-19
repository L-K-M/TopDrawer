import AppKit

/// Activates Top Drawer for a modal prompt (an alert or open panel) raised over an
/// open drawer, and hands activation back to the user's app once the drawer closes.
///
/// Top Drawer is an accessory agent whose drawers never activate it, so a prompt
/// raised from a drawer has to activate the app to receive key focus. Nothing
/// re-activated the user's app afterwards, though: with no ordinary window of our
/// own left, their next keystrokes went nowhere until they clicked back into their
/// app — the focus theft the non-activating drawers exist to avoid.
enum ModalActivation {

    /// Activates Top Drawer and runs `modal`, a prompt over the open drawer.
    ///
    /// Activation stays with Top Drawer when the prompt ends: the drawer is still
    /// open and needs the keyboard (Esc, arrows, type-to-find), and re-activating
    /// the user's app now would take the drawer's key status with it. Closing the
    /// drawer hands activation back instead (`handBackIfIdle`).
    static func runOverDrawer<Result>(_ modal: () -> Result) -> Result {
        // Deprecated on macOS 14, but cooperative `activate()` may be declined for an
        // accessory agent, and the prompt must get the keyboard.
        NSApp.activate(ignoringOtherApps: true)
        return modal()
    }

    /// Whether activation should return to the app with `previousPID` once the
    /// drawer closes: only another app that is still running, and only while Top
    /// Drawer still holds activation (`isActive`). If the user switched to another
    /// app meanwhile, that app keeps it. When Top Drawer itself was frontmost
    /// (Settings had focus), it keeps it.
    static func shouldHandBack(isActive: Bool, toPID previousPID: pid_t?, isTerminated: Bool,
                               ownPID: pid_t) -> Bool {
        guard isActive, let previousPID, !isTerminated else { return false }
        return previousPID != ownPID
    }

    /// Re-activates `previous` when Top Drawer is active with no ordinary window of
    /// its own — the state a prompt over the drawer, or a click inside its pop-up or
    /// preview, leaves behind, since those windows activate the app — so closing the
    /// drawer returns the keyboard to the app the user was in.
    static func handBackIfIdle(to previous: NSRunningApplication?) {
        guard NSApp.isActive, !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        handBack(to: previous)
    }

    private static func handBack(to previous: NSRunningApplication?) {
        guard let previous,
              shouldHandBack(isActive: NSApp.isActive, toPID: previous.processIdentifier,
                             isTerminated: previous.isTerminated,
                             ownPID: ProcessInfo.processInfo.processIdentifier) else { return }
        // Cooperative activation (macOS 14): yield explicitly, then ask it to activate.
        NSApp.yieldActivation(to: previous)
        previous.activate()
    }
}
