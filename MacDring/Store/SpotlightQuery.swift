import Foundation

/// A one-shot Spotlight (`NSMetadataQuery`) lookup that backs the live **Fresh** tab
/// and the *system* source of the **Recents** tab. Unlike the synchronous listers,
/// Spotlight gathers asynchronously, so this delivers its results through a
/// completion once gathering finishes, then stops. It reads only the **index** (file
/// locations + dates), never file contents, so — like the other listers — it needs
/// no special permission (and adds no global monitor or event tap).
final class SpotlightQuery {

    /// What to rank by: most-recently **used** (Recents) or most-recently **added**
    /// (Fresh — i.e. downloaded / copied / saved into its folder).
    enum Mode {
        case lastUsed
        case dateAdded

        /// The Spotlight metadata attribute this mode sorts and filters on.
        var attribute: String {
            switch self {
            case .lastUsed: return "kMDItemLastUsedDate"
            case .dateAdded: return "kMDItemDateAdded"
            }
        }

        /// How far back to look. "Recent" is the whole point, so a window keeps the
        /// query light and the result meaningful (Spotlight needn't gather the entire
        /// index).
        var window: TimeInterval {
            switch self {
            case .lastUsed: return 90 * 24 * 60 * 60
            case .dateAdded: return 30 * 24 * 60 * 60
            }
        }
    }

    /// A single indexed file: where it lives, its display name, and the ranking date.
    struct Result: Equatable {
        let url: URL
        let name: String
        let date: Date
    }

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
