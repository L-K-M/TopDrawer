import AppKit

/// Opens a drawer item: launches/activates an app, opens a file or folder in its
/// default handler, or opens a URL. Uses `NSWorkspace`, so it needs no special
/// permission.
enum ItemLauncher {

    enum LaunchError: Error {
        case unresolvedTarget
        case unsupportedItemKind(ItemKind)
        case workspaceOpenFailed(URL)
        case applicationOpenFailed(URL, Error)
    }

    typealias LaunchResult = Result<URL, LaunchError>
    typealias LaunchCompletion = (LaunchResult) -> Void

    /// Gates all completion paths so callers always receive one result on the main
    /// thread, including the asynchronous application-open callback.
    private final class CompletionRelay {
        private let lock = NSLock()
        private var didComplete = false
        private let completion: LaunchCompletion

        init(_ completion: @escaping LaunchCompletion) {
            self.completion = completion
        }

        func complete(_ result: LaunchResult) {
            lock.lock()
            guard !didComplete else {
                lock.unlock()
                return
            }
            didComplete = true
            lock.unlock()

            let deliver = { self.completion(result) }
            if Thread.isMainThread {
                deliver()
            } else {
                DispatchQueue.main.async(execute: deliver)
            }
        }
    }

    /// Launches the item and reports the confirmed target URL, or the reason opening
    /// failed. The completion fires exactly once on the main thread.
    static func launch(_ item: DrawerItem, completion: @escaping LaunchCompletion) {
        launch(
            item,
            resolveURL: { BookmarkResolver.url(for: $0) },
            openApplication: { url, reply in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                    reply(error)
                }
            },
            openURL: { NSWorkspace.shared.open($0) },
            completion: completion
        )
    }

    /// Injectable workspace seams keep result handling deterministic in unit tests.
    static func launch(
        _ item: DrawerItem,
        resolveURL: (DrawerItem) -> URL?,
        openApplication: (URL, @escaping (Error?) -> Void) -> Void,
        openURL: (URL) -> Bool,
        completion: @escaping LaunchCompletion
    ) {
        let relay = CompletionRelay(completion)
        guard item.kind != .group else {
            relay.complete(.failure(.unsupportedItemKind(item.kind)))
            return
        }
        guard let url = resolveURL(item) else {
            relay.complete(.failure(.unresolvedTarget))
            return
        }

        switch item.kind {
        case .application:
            openApplication(url) { error in
                if let error {
                    NSLog("MacDring: failed to launch \(url.lastPathComponent): \(error.localizedDescription)")
                    relay.complete(.failure(.applicationOpenFailed(url, error)))
                } else {
                    relay.complete(.success(url))
                }
            }
        case .file, .folder, .url, .trash, .disk, .cloud:
            // trash -> Trash folder; disk -> the volume; cloud -> the folder, in Finder
            if openURL(url) {
                relay.complete(.success(url))
            } else {
                NSLog("MacDring: failed to open \(url.lastPathComponent)")
                relay.complete(.failure(.workspaceOpenFailed(url)))
            }
        case .group:
            break   // handled before URL resolution; groups open in the drawer instead
        }
    }

    /// Reveals a file or folder item in Finder.
    static func revealInFinder(_ item: DrawerItem) {
        guard item.kind != .url, let url = BookmarkResolver.url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens dropped `urls` with a specific application item (drop-onto-app).
    static func open(_ urls: [URL], withApp appItem: DrawerItem) {
        guard !urls.isEmpty, let appURL = BookmarkResolver.url(for: appItem) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("MacDring: open-with failed: \(error.localizedDescription)")
            }
        }
    }
}
