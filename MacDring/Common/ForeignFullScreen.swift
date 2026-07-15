import AppKit
import CoreGraphics

/// Detects whether **another application** currently has a native full-screen window
/// covering a given display.
///
/// Why the drawer needs this: the drawer is a non-activating panel that normally
/// `makeKey()`s on open so its type-to-find field, drag-to-reorder, and Esc work with
/// no prior click. Over another app's native full-screen **Space**, taking key focus
/// binds our `.accessory` app's window to its *own* (hidden) desktop Space, so the
/// window server sites the now-key drawer there and it never appears on the visible
/// full-screen Space — the drawer looked simply absent. The tab pill never becomes key
/// (it only `orderFrontRegardless()`es), which is exactly why it has always shown over
/// full-screen. So the drawer opens **non-key** when — and only when — it's opening
/// over a foreign full-screen Space, matching the tab's proven-working recipe there.
///
/// Reads only window **geometry + owner PID** from the window server
/// (`CGWindowListCopyWindowInfo`), never window titles, so it needs **no** Screen
/// Recording permission — keeping the app's no-scary-permissions promise.
enum ForeignFullScreen {

    /// Whether some *other* app has a native full-screen window covering `screen` now.
    /// Conservative: matches only a window that exactly fills the display, so a merely
    /// zoomed/maximized window (which stops short of the hidden menu bar) is not
    /// mistaken for full-screen — a false positive would needlessly cost the drawer its
    /// eager key focus on the ordinary desktop, so we bias hard against it.
    static func covers(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        // CGDisplayBounds is in the same top-left global coordinate space that
        // CGWindowListCopyWindowInfo reports window bounds in, so they compare directly
        // with no manual flip.
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        let myPID = NSRunningApplication.current.processIdentifier

        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        for info in infos {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != myPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            if covers(windowBounds: bounds, displayBounds: displayBounds) { return true }
        }
        return false
    }

    /// Pure: does `windowBounds` fill `displayBounds`? A native full-screen window
    /// exactly covers its display (menu bar hidden); a small tolerance absorbs
    /// sub-pixel/backing rounding. Origin is matched too, so a same-sized window on a
    /// *different* display doesn't count.
    static func covers(windowBounds: CGRect, displayBounds: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(windowBounds.minX - displayBounds.minX) <= tolerance &&
        abs(windowBounds.minY - displayBounds.minY) <= tolerance &&
        abs(windowBounds.width - displayBounds.width) <= tolerance &&
        abs(windowBounds.height - displayBounds.height) <= tolerance
    }
}
