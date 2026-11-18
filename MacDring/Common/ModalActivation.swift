import AppKit

/// Runs a modal prompt (an alert or open panel) that needs the keyboard, then hands
/// activation back to the app that was frontmost before it.
///
/// Top Drawer is an accessory agent whose drawers never activate it, so a prompt
/// raised from a drawer has to activate the app to receive key focus. Nothing
/// re-activated the user's app once the prompt ended, though: with no ordinary
/// window of our own left, their next keystrokes went nowhere until they clicked
/// back into their app — the focus theft the non-activating drawers exist to avoid.
enum ModalActivation {

    /// Activates Top Drawer, runs `modal`, and returns its result after re-activating
    /// the previously frontmost app (when that was another, still-running app).
    static func run<Result>(_ modal: () -> Result) -> Result {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        defer { handBack(to: previous) }
        return modal()
    }

    /// Whether activation should return to the app with `previousPID` once the
    /// prompt ends: only another app that is still running. When Top Drawer itself
    /// was frontmost (Settings had focus), it keeps it.
    static func shouldHandBack(toPID previousPID: pid_t?, isTerminated: Bool, ownPID: pid_t) -> Bool {
        guard let previousPID, !isTerminated else { return false }
        return previousPID != ownPID
    }

    private static func handBack(to previous: NSRunningApplication?) {
        guard let previous,
              shouldHandBack(toPID: previous.processIdentifier, isTerminated: previous.isTerminated,
                             ownPID: ProcessInfo.processInfo.processIdentifier) else { return }
        // Cooperative activation (macOS 14): yield explicitly, then ask it to activate.
        NSApp.yieldActivation(to: previous)
        previous.activate()
    }
}
