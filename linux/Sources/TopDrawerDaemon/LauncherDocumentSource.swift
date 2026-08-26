import Foundation

/// Reads the persisted Top Drawer launcher document as raw JSON text.
///
/// The macOS app owns and mutates this file through MacDring's `TabStore`
/// (at `$XDG_DATA_HOME/MacDring/launcher.json` on Linux — `.applicationSupportDirectory`
/// maps to `$XDG_DATA_HOME`). The daemon only *reads* it, so at the LP-16 skeleton
/// stage it serves the bytes verbatim rather than depending on MacDring's
/// (module-internal) model types. LP-17+ replace this with a decoded, daemon-owned
/// document as the store/lister types gain a public surface.
///
/// Cross-platform and dependency-free so it can be unit-tested on either CI.
public struct LauncherDocumentSource: Sendable {

    /// The launcher document's location on disk.
    public let url: URL

    public init(url: URL) { self.url = url }

    /// The default location: `$XDG_DATA_HOME/MacDring/launcher.json` on Linux
    /// (Foundation's `.applicationSupportDirectory` resolves to `$XDG_DATA_HOME`),
    /// mirroring `TabStore.defaultStoreURL`. The legacy `MacDring` directory name is
    /// deliberate — the app kept it across the rename to Top Drawer so it wouldn't
    /// orphan every existing user's saved layout, and the daemon must read the same
    /// path the app writes.
    public static func `default`(fileManager: FileManager = .default) -> LauncherDocumentSource {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: false))
            ?? fileManager.temporaryDirectory
        let url = base.appendingPathComponent("MacDring", isDirectory: true)
            .appendingPathComponent("launcher.json")
        return LauncherDocumentSource(url: url)
    }

    /// The launcher JSON, or `"{}"` when the file is absent or unreadable, so
    /// `GetDocument` always hands the client valid, parseable JSON. (Serving the
    /// bytes verbatim is deliberate at LP-16 — the daemon doesn't yet re-encode a
    /// decoded document.)
    public func rawJSON() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "{}"
    }

    /// The document file's modification date, or `nil` when it's absent. The
    /// change watcher polls this to decide when to emit `DocumentChanged`.
    public func modificationDate(fileManager: FileManager = .default) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
