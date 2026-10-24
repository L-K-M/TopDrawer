import Foundation
import MacDring
#if canImport(FoundationXML)
import FoundationXML   // XMLParser lives here on Linux, in Foundation on macOS.
#endif
#if os(Linux)
import CShims
#endif

/// One recents/fresh entry as the daemon reports it over `GetRecents`. `date` is Unix
/// epoch seconds (the ranking date: last-used for Recents, date-added for Fresh).
public struct RecentEntry: Codable, Equatable, Sendable {
    public let path: String
    public let name: String
    public let date: Double
}

extension RecentEntry {
    init(_ hit: RecentFileHit) {
        self.init(path: hit.url.path, name: hit.name, date: hit.date.timeIntervalSince1970)
    }
}

// MARK: - recently-used.xbel (the system Recents source)

/// Parses `recently-used.xbel` (the freedesktop/GTK recent-files list). Pure — takes
/// the file's text — so it unit-tests against fixtures on either platform. Each
/// `<bookmark href="file://…" visited="…" …>` becomes a `RecentFileHit` ranked by its
/// `visited` (last-opened) timestamp, falling back to `modified` then `added`.
public enum XbelParser {
    public static func parse(_ xml: String) -> [RecentFileHit] {
        let collector = BookmarkCollector()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = collector
        parser.parse()
        return collector.hits
    }
}

private final class BookmarkCollector: NSObject, XMLParserDelegate {
    var hits: [RecentFileHit] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        guard elementName == "bookmark",
              let href = attributes["href"],
              let url = URL(string: href), url.isFileURL else { return }
        // Rank by when the file was last opened; older exporters omit `visited`, so fall
        // back to `modified` then `added`.
        guard let stamp = attributes["visited"] ?? attributes["modified"] ?? attributes["added"],
              let date = Self.parseTimestamp(stamp) else { return }
        let fileURL = url.standardizedFileURL
        hits.append(RecentFileHit(url: fileURL, name: fileURL.lastPathComponent, date: date))
    }

    /// XBEL timestamps are ISO-8601 (`2024-06-03T12:00:00Z`), sometimes with fractional
    /// seconds. Try both.
    private static let isoPlain = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func parseTimestamp(_ s: String) -> Date? {
        isoPlain.date(from: s) ?? isoFractional.date(from: s)
    }
}

/// The system Recents source: `$XDG_DATA_HOME/recently-used.xbel`, parsed and filtered
/// to the last-used window.
public enum RecentlyUsedFile {
    /// `$XDG_DATA_HOME/recently-used.xbel` (default `~/.local/share/recently-used.xbel`).
    /// A relative `$XDG_DATA_HOME` is treated as unset (XDG spec), matching TrashLocation.
    public static func location(environment: [String: String], home: URL) -> URL {
        let base: URL
        if let xdg = environment["XDG_DATA_HOME"], xdg.hasPrefix("/") {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = home.appendingPathComponent(".local/share", isDirectory: true)
        }
        return base.appendingPathComponent("recently-used.xbel")
    }

    /// The most-recently-used files from `xbel`, within the last-used window, newest
    /// first, capped to `limit`. Pure over an injected clock + file text.
    public static func hits(xbel: String, limit: Int, now: Date = Date()) -> [RecentFileHit] {
        let cutoff = now.addingTimeInterval(-RecentQueryMode.lastUsed.window)
        return Array(XbelParser.parse(xbel)
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
            .prefix(limit))
    }
}

// MARK: - Birth time (Fresh dateAdded)

#if os(Linux)
/// The Linux `dateAdded` for `FreshScanner`: the file's birth time via `statx`
/// (`CShims.topdrawer_file_btime`), falling back to its modification time when the
/// filesystem doesn't record a birth time — FreshScanner's ladder, minus the macOS
/// Date-Added attribute Linux doesn't have.
public func linuxDateAdded(_ url: URL) -> Date? {
    if let nanos = birthTimeNanos(ofPath: url.path) {
        return Date(timeIntervalSince1970: TimeInterval(nanos) / 1e9)
    }
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attrs?[.modificationDate] as? Date
}

private func birthTimeNanos(ofPath path: String) -> Int64? {
    let value = path.withCString { topdrawer_file_btime($0) }
    return value >= 0 ? value : nil
}
#endif

/// The Fresh source: `FreshScanner`'s ranking over the standard landing zones, with the
/// Linux birth-time `dateAdded`. (Empty off Linux, where there's no birth-time shim.)
public enum LinuxFresh {
    public static func hits(scopes: [URL] = FreshLister.scopes(), limit: Int, now: Date = Date()) -> [RecentFileHit] {
        #if os(Linux)
        return FreshScanner.results(scopes: scopes, limit: limit, now: now, dateAdded: linuxDateAdded)
        #else
        return []
        #endif
    }
}

// MARK: - Provider seam

/// The daemon's source of Recents/Fresh hits: `LinuxRecentsProvider` reads the real
/// `recently-used.xbel` and runs the fresh scan in production; a fake drives the D-Bus
/// tests deterministically.
public protocol RecentsProviding: Sendable {
    /// System recents (from `recently-used.xbel`), newest first, capped to `limit`.
    func systemRecents(limit: Int) -> [RecentFileHit]
    /// Freshly-arrived files (birth-time ranked), newest first, capped to `limit`.
    func fresh(limit: Int) -> [RecentFileHit]
}

public struct LinuxRecentsProvider: RecentsProviding {
    private let xbelURL: URL
    private let freshScopes: [URL]

    public init(xbelURL: URL, freshScopes: [URL] = FreshLister.scopes()) {
        self.xbelURL = xbelURL
        self.freshScopes = freshScopes
    }

    public func systemRecents(limit: Int) -> [RecentFileHit] {
        guard let xml = try? String(contentsOf: xbelURL, encoding: .utf8) else { return [] }
        // The xbel keeps entries for files long since moved or trashed; macOS recents
        // (Spotlight-backed) only ever list live files. Filter here — the impure
        // boundary — so `RecentlyUsedFile.hits` stays pure/testable; over-fetch so dead
        // entries don't starve the result below `limit`.
        return Array(RecentlyUsedFile.hits(xbel: xml, limit: limit * 4)
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .prefix(limit))
    }

    public func fresh(limit: Int) -> [RecentFileHit] {
        LinuxFresh.hits(scopes: freshScopes, limit: limit)
    }
}

/// A `RecentsProviding` decorator that serves the wrapped provider's last result for
/// `ttl` seconds. `GetRecents` is served per tab, so a frontend holding several
/// recents/fresh tabs would otherwise pay the full xbel parse + the fresh statx sweep
/// once per tab per refresh.
///
/// `invalidate()` drops both buckets; the daemon calls it before every `RecentsChanged`
/// signal, so a cached snapshot never survives a change the watchers saw. Changes the
/// daemon can't see (an xbel rewrite preserving mtime) age out within `ttl` anyway.
public final class CachedRecentsProvider: RecentsProviding, @unchecked Sendable {
    private enum Bucket { case system, fresh }

    private let wrapped: RecentsProviding
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var cached: [Bucket: (at: Date, limit: Int, hits: [RecentFileHit])] = [:]

    public init(wrapping wrapped: RecentsProviding, ttl: TimeInterval = 2,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.wrapped = wrapped
        self.ttl = ttl
        self.now = now
    }

    public func systemRecents(limit: Int) -> [RecentFileHit] {
        serve(.system, limit: limit) { wrapped.systemRecents(limit: $0) }
    }

    public func fresh(limit: Int) -> [RecentFileHit] {
        serve(.fresh, limit: limit) { wrapped.fresh(limit: $0) }
    }

    public func invalidate() {
        lock.lock()
        cached = [:]
        lock.unlock()
    }

    private func serve(_ bucket: Bucket, limit: Int,
                       fetch: (Int) -> [RecentFileHit]) -> [RecentFileHit] {
        lock.lock()
        // A cached fetch whose requested limit covers this call is complete for it,
        // even when the provider returned fewer hits than asked.
        if let entry = cached[bucket], entry.limit >= limit,
           now().timeIntervalSince(entry.at) < ttl {
            lock.unlock()
            return Array(entry.hits.prefix(limit))
        }
        lock.unlock()
        // Fetch outside the lock — a slow provider (the statx sweep) must not serialize
        // unrelated buckets. Concurrent misses may both fetch; last writer wins, which
        // is fine: same inputs, same result.
        let hits = fetch(limit)
        lock.lock()
        cached[bucket] = (now(), limit, hits)
        lock.unlock()
        return hits
    }
}

// MARK: - Tab lookup (raw launcher JSON)

/// The bits of a tab the daemon needs to answer `GetRecents`, read straight from the
/// launcher JSON so the daemon doesn't depend on MacDring's (module-internal) `Tab`
/// type — the same raw-JSON approach `LauncherDocumentSource` uses.
public struct TabInfo: Equatable {
    public let id: String
    public let kind: String
    public let recentsSource: String?   // "macDring" / "system" / "both" for a recents tab

    /// Whether this recents tab draws (in part) from the system source
    /// (`recently-used.xbel`) — recentsSource `system` or `both`. The single predicate
    /// both `recentsHits` and the `RecentsChanged` fan-out use, so they can't drift
    /// (a macDring-only tab neither serves xbel data nor should be signalled on an xbel
    /// change).
    public var servesSystemRecents: Bool {
        let source = recentsSource ?? "macDring"
        return source == "system" || source == "both"
    }

    /// Whether this recents tab draws (in part) from Top Drawer's own launch history
    /// (`RecentsStore`) — recentsSource `macDring` (the default) or `both`. Populated by
    /// `Launch` recording into the recorder (LP-19).
    public var servesMacDringRecents: Bool {
        let source = recentsSource ?? "macDring"
        return source == "macDring" || source == "both"
    }
}

public enum LauncherTabs {
    /// Every tab in the launcher JSON, as `TabInfo`. Tolerant of a malformed document
    /// (returns an empty list).
    public static func all(in json: String) -> [TabInfo] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tabs = root["tabs"] as? [[String: Any]] else { return [] }
        return tabs.compactMap { tab in
            guard let id = tab["id"] as? String else { return nil }
            return TabInfo(id: id,
                           kind: tab["kind"] as? String ?? "items",
                           recentsSource: tab["recentsSource"] as? String)
        }
    }

    public static func find(id: String, in json: String) -> TabInfo? {
        all(in: json).first { $0.id == id }
    }
}
