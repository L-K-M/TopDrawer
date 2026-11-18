import Foundation

/// Fetches releases for a GitHub repository over the public REST API (no token —
/// unauthenticated requests are rate-limited to 60/hour per IP, ample for a
/// once-a-day check).
///
/// Reusable across apps — depends only on Foundation.
struct GitHubReleaseClient {
    let owner: String
    let repo: String
    var session: URLSession = .shared

    enum ClientError: LocalizedError {
        case badResponse(Int)
        case noReleases
        case badURL

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "GitHub returned HTTP \(code)."
            case .noReleases: return "No published releases were found."
            case .badURL: return "Couldn't build a valid GitHub API URL."
            }
        }
    }

    /// The newest published release. When `includePrereleases` is false this uses the
    /// repo's `releases/latest` endpoint (which already excludes drafts and
    /// pre-releases); otherwise it scans the recent releases and returns the
    /// highest-versioned non-draft one.
    func latestRelease(includePrereleases: Bool) async throws -> GitHubRelease {
        if includePrereleases {
            let releases = try await prereleaseScan()
            let newest = releases
                .filter { !$0.draft }
                .max { (SemanticVersion($0.tagName) ?? .zero) < (SemanticVersion($1.tagName) ?? .zero) }
            guard let newest else { throw ClientError.noReleases }
            return newest
        }
        return try await fetch(GitHubRelease.self, path: "releases/latest")
    }

    /// How many release-list pages a prerelease scan reads before stopping. GitHub
    /// orders releases by creation date, not version, so a higher version can sit on
    /// an older page; the scan is bounded so a repo with a long history cannot make
    /// the check unbounded.
    static let maximumPrereleasePages = 10
    /// GitHub's maximum `per_page` for the release list.
    static let releasesPerPage = 100

    /// Every release the bounded scan can see, oldest page last. Stops early on a
    /// short page (the end of the list).
    private func prereleaseScan() async throws -> [GitHubRelease] {
        var releases: [GitHubRelease] = []
        for page in 1...Self.maximumPrereleasePages {
            let batch = try await fetch([GitHubRelease].self,
                                        path: "releases?per_page=\(Self.releasesPerPage)&page=\(page)")
            releases += batch
            if batch.count < Self.releasesPerPage { break }
        }
        return releases
    }

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/\(path)") else {
            throw ClientError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub requires a User-Agent header; use the app's bundle id.
        request.setValue(Bundle.main.bundleIdentifier ?? "UpdateChecker", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse(-1) }
        // 404 from the latest endpoint means the repo has no published (non-draft,
        // non-prerelease) release yet — report that rather than a raw HTTP code.
        if http.statusCode == 404 { throw ClientError.noReleases }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.badResponse(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
