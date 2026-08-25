import Foundation

#if os(macOS)
/// A one-shot Spotlight (`NSMetadataQuery`) lookup that backs the live **Fresh** tab
/// and the *system* source of the **Recents** tab. Unlike the synchronous listers,
/// Spotlight gathers asynchronously, so this delivers its results through a
/// completion once gathering finishes, then stops. It reads only the **index** (file
/// locations + dates), never file contents, so — like the other listers — it needs
/// no special permission (and adds no global monitor or event tap).
///
/// The `RecentFilesQuerying` vocabulary (`RecentFileHit`, `RecentQueryMode`) lives in
/// `RecentFilesQuery.swift` so the pure listers compile on Linux; this Spotlight
/// implementation is macOS-only (`NSMetadataQuery` has no Linux equivalent). The old
/// nested names stay as typealiases so existing call sites are unchanged.
final class SpotlightQuery: RecentFilesQuerying {

    typealias Result = RecentFileHit
    typealias Mode = RecentQueryMode

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var completion: (([Result]) -> Void)?
    private var attribute = ""
    private var limit = 0

    /// Whether a lookup is currently gathering (started and not yet finished or
    /// cancelled). Lets callers avoid restarting — and thereby starving — a query
    /// that is already collecting the results they want.
    var isGathering: Bool { query != nil }

    /// Starts a fresh lookup, cancelling any in-flight one. `scopes` are the directory
    /// URLs to search under. `completion` fires once on the main queue with the newest
    /// `limit` results (most-recent first), after which the query stops.
    func start(mode: Mode, scopes: [URL], limit: Int, completion: @escaping ([Result]) -> Void) {
        cancel()
        self.completion = completion
        self.attribute = mode.attribute
        self.limit = limit

        let query = NSMetadataQuery()
        let cutoff = Date(timeIntervalSinceNow: -mode.window) as NSDate
        query.predicate = NSPredicate(format: "%K >= %@", mode.attribute, cutoff)
        query.searchScopes = scopes
        query.sortDescriptors = [NSSortDescriptor(key: mode.attribute, ascending: false)]
        query.operationQueue = .main

        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in self?.finish() }

        self.query = query
        guard query.start() else {
            let completion = self.completion
            cancel()
            completion?([])
            return
        }
    }

    /// Stops any in-flight lookup and forgets its completion (no callback will fire).
    func cancel() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        query?.stop()
        query = nil
        completion = nil
    }

    private func finish() {
        guard let query else { return }
        query.disableUpdates()
        let results = SpotlightQuery.results(from: query, attribute: attribute, limit: limit)
        let completion = self.completion
        cancel()
        completion?(results)
    }

    /// Reads the newest `limit` items out of a finished query (already sorted by the
    /// ranking attribute, newest first); skips any item missing a usable path.
    private static func results(from query: NSMetadataQuery, attribute: String, limit: Int) -> [Result] {
        var out: [Result] = []
        for index in 0..<query.resultCount {
            if out.count >= limit { break }
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? url.lastPathComponent
            let date = item.value(forAttribute: attribute) as? Date ?? .distantPast
            out.append(Result(url: url, name: name, date: date))
        }
        return out
    }
}
#endif
