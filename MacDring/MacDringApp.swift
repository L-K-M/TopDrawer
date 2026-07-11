import AppKit

/// Program entry point.
///
/// Top Drawer is a menu-bar agent (`LSUIElement`), so it runs as an `.accessory`
/// app with no Dock icon. A plain `NSApplication` lifecycle (rather than the
/// SwiftUI `App` scene) keeps full control over the borderless tab/drawer panels
/// on macOS 13+.
@main
enum MacDringMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
