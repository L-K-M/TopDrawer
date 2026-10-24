import Foundation
#if canImport(AppKit)
import AppKit   // NSWorkspace: Launch Services lookup + the open-with backend
#endif

/// "Open With" support for drawer items: enumerates the applications Launch Services
/// says can open an item's target, and opens the target with the chosen one.
///
/// Like `ItemLauncher`, the result path is a pure seam-injected core
/// (`open(_:withApplicationAt:resolveURL:isValidApplication:openURLs:completion:)`);
/// the macOS entry points fill those seams with `NSWorkspace`. Controllers and views
/// go through this service and never touch `NSWorkspace` themselves (AGENTS.md's
/// layering rule), which keeps the "no special permission" promise: the workspace
/// APIs used here need none.
enum ItemActionService {

    /// Why an Open With request failed. The drawer surfaces `localizedDescription`
    /// in its error banner, so each case names an actionable cause.
    enum ActionError: Error, LocalizedError, Equatable {
        /// The item's bookmark/URL resolved to nothing — the target is gone.
        case unresolvedTarget
        /// The chosen application URL isn't an existing local `.app` bundle.
        case invalidApplication(URL)
        /// The workspace refused the open; `underlying` carries its reason.
        case openFailed(target: URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .unresolvedTarget:
                return "The item's target can't be found."
            case .invalidApplication(let url):
                return "\(url.deletingPathExtension().lastPathComponent) isn't a usable application."
            case .openFailed(_, let underlying):
                return underlying.localizedDescription
            }
        }

        static func == (lhs: ActionError, rhs: ActionError) -> Bool {
            switch (lhs, rhs) {
            case (.unresolvedTarget, .unresolvedTarget): return true
            case (.invalidApplication(let a), .invalidApplication(let b)): return a == b
            case (.openFailed(let ta, _), .openFailed(let tb, _)): return ta == tb
            default: return false
            }
        }
    }

    /// A usable Open With candidate: an existing local `.app` bundle directory.
    /// `urlsForApplications` can return stale or non-bundle entries, so callers and
    /// `open` both re-check rather than trusting the list.
    static func isValidApplication(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else { return false }
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// The seam-injected core behind the macOS `open`. `completion` fires exactly
    /// once on the main thread with the resolved target URL or the failure.
    ///
    /// Resolving `item`'s bookmark at invocation time (not earlier, in the caller)
    /// matters: a persisted item keeps working after its target moves, and resolving
    /// late means we open the file where it is *now*.
    static func open(
        _ item: DrawerItem,
        withApplicationAt appURL: URL,
        resolveURL: (DrawerItem) -> URL?,
        isValidApplication: (URL) -> Bool,
        openURLs: (_ urls: [URL], _ application: URL, _ reply: @escaping (Error?) -> Void) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let relay = CompletionRelay(completion)
        guard isValidApplication(appURL) else {
            relay.complete(.failure(ActionError.invalidApplication(appURL)))
            return
        }
        guard let target = resolveURL(item) else {
            relay.complete(.failure(ActionError.unresolvedTarget))
            return
        }
        openURLs([target], appURL) { error in
            if let error {
                NSLog("Top Drawer: open-with failed for \(target.lastPathComponent): \(error.localizedDescription)")
                relay.complete(.failure(ActionError.openFailed(target: target, underlying: error)))
            } else {
                relay.complete(.success(target))
            }
        }
    }

    /// Gates every completion path so callers always receive exactly one result on
    /// the main thread — same idiom as `ItemLauncher.CompletionRelay`.
    private final class CompletionRelay {
        private let lock = NSLock()
        private var didComplete = false
        private let completion: (Result<URL, Error>) -> Void

        init(_ completion: @escaping (Result<URL, Error>) -> Void) {
            self.completion = completion
        }

        func complete(_ result: Result<URL, Error>) {
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
}

#if canImport(AppKit)
extension ItemActionService {

    /// An application that can open a given item, for the "Open With" menu.
    /// `id` is the bundle URL — the stable identity (a renamed app still hashes
    /// to itself).
    struct Application: Identifiable {
        let id: URL
        /// The app bundle's URL; handed back to `open(_:withApplicationAt:completion:)`.
        let url: URL
        /// Finder-style name (no `.app` suffix).
        let name: String
        /// The app's own icon via `NSWorkspace`.
        let icon: NSImage
    }

    /// The apps Launch Services reports as able to open `item`'s resolved target,
    /// deduplicated, filtered to real local `.app` bundles, and sorted by name.
    /// Empty for items without a resolvable target (a group, a dead bookmark).
    static func applications(for item: DrawerItem) -> [Application] {
        guard let url = BookmarkResolver.url(for: item) else { return [] }
        return applications(
            toOpen: url,
            applicationURLs: { NSWorkspace.shared.urlsForApplications(toOpen: $0) },
            icon: { NSWorkspace.shared.icon(forFile: $0.path) }
        )
    }

    /// The validate/dedup/sort half, injectable so a test needs no Launch Services.
    static func applications(
        toOpen url: URL,
        applicationURLs: (URL) -> [URL],
        icon: (URL) -> NSImage
    ) -> [Application] {
        var seen = Set<URL>()
        let apps = applicationURLs(url).compactMap { appURL -> Application? in
            let identity = appURL.standardizedFileURL
            guard seen.insert(identity).inserted, isValidApplication(appURL) else { return nil }
            return Application(id: identity, url: appURL,
                               name: DrawerItem.kindAndName(for: appURL).name,
                               icon: icon(appURL))
        }
        return apps.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
    }

    /// Opens `item` with the application bundle at `appURL`. The completion fires
    /// exactly once on the main thread with the resolved target URL (so callers can
    /// record recents) or the failure reason.
    static func open(_ item: DrawerItem, withApplicationAt appURL: URL,
                     completion: @escaping (Result<URL, Error>) -> Void) {
        open(item, withApplicationAt: appURL,
             resolveURL: { BookmarkResolver.url(for: $0) },
             isValidApplication: { isValidApplication($0) },
             openURLs: { urls, app, reply in
                 let configuration = NSWorkspace.OpenConfiguration()
                 configuration.activates = true
                 NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration) { _, error in
                     reply(error)
                 }
             },
             completion: completion)
    }
}
#endif
