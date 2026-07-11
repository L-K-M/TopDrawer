import AppKit

/// Maps between live `NSScreen`s and the stable display-UUID strings stored in
/// `ScreenAnchor`, and notifies when the display configuration changes. The UUID
/// (`CGDisplayCreateUUIDFromDisplayID`) is stable across reboots and
/// reconnections, which is what makes tab restore stable. See PLAN.md §6.
final class DisplayRegistry {

    /// Called on the main thread when displays are added, removed, or reconfigured.
    var onChange: (() -> Void)?

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onChange?()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The stable UUID string for a screen, or `nil` if it can't be determined.
    func uuid(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return DisplayRegistry.uuidString(for: CGDirectDisplayID(number.uint32Value))
    }

    /// The currently-connected `NSScreen` for a stored UUID, or `nil` if that
    /// display isn't attached right now.
    func screen(for uuid: String) -> NSScreen? {
        NSScreen.screens.first { self.uuid(for: $0) == uuid }
    }

    /// The deterministic primary display (the menu-bar display). `NSScreen.main`
    /// follows keyboard/window focus, which can be a Top Drawer drawer panel.
    static var primaryScreen: NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    /// The primary screen's UUID — the fallback target for unknown displays (e.g.
    /// importing a layout on a new machine).
    func mainScreenUUID() -> String? {
        Self.primaryScreen.flatMap { uuid(for: $0) }
    }

    /// Converts a `CGDirectDisplayID` into its persistent UUID string.
    static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let cfString = CFUUIDCreateString(nil, cfUUID) else { return nil }
        return cfString as String
    }
}
