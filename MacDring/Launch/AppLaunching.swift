import Foundation

/// The launch seam `ItemLauncher` opens through, named so a Linux backend has a shape to
/// fill: resolve a stored item to its URL, open an application (async, replies with an
/// error or nil), and open a URL in its default handler (sync). macOS conforms with
/// `NSWorkspace` (`SystemAppLauncher`); the pure
/// `ItemLauncher.launch(_:resolveURL:openApplication:openURL:completion:)` takes these
/// same three seams as closures. See PLAN.md §LP-12.
protocol AppLaunching {
    func resolveURL(for item: DrawerItem) -> URL?
    func openApplication(at url: URL, reply: @escaping (Error?) -> Void)
    func openURL(_ url: URL) -> Bool
}

extension ItemLauncher {
    /// Launches `item` through an `AppLaunching` backend, forwarding to the pure core.
    static func launch(_ item: DrawerItem, using launcher: AppLaunching,
                       completion: @escaping LaunchCompletion) {
        launch(item,
               resolveURL: { launcher.resolveURL(for: $0) },
               openApplication: { launcher.openApplication(at: $0, reply: $1) },
               openURL: { launcher.openURL($0) },
               completion: completion)
    }
}

#if canImport(AppKit)
import AppKit

/// macOS `AppLaunching`: opens through `NSWorkspace`, which needs no special permission.
struct SystemAppLauncher: AppLaunching {
    func resolveURL(for item: DrawerItem) -> URL? { BookmarkResolver.url(for: item) }

    func openApplication(at url: URL, reply: @escaping (Error?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in reply(error) }
    }

    func openURL(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
}
#endif
