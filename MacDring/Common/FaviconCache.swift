import AppKit
import ImageIO

/// Best-effort favicon cache for web-link (`.url`) items: fetches a host's
/// `https://<host>/favicon.ico` once, keeps a small downscaled copy in memory, and
/// hands it back so the drawer can swap the generic globe for the site's own icon.
///
/// - Concurrent requests for the same host share one in-flight fetch (late callers
///   await it), so duplicate link items never race each other into a miss.
/// - Only a **definitive** miss (non-200 response, undecodable image) is remembered;
///   a transport error — offline drawer open, flaky Wi-Fi — is *not* pinned, so the
///   next drawer open retries.
/// - Icons are downscaled on store (favicon.ico files are often multi-rep ICOs or
///   oversized PNGs) and the cache is capped, oldest-first — it's a menu-bar agent
///   that runs for weeks; nothing here may grow without bound.
///
/// The cache lives for the app session only (no on-disk persistence).
/// `@unchecked Sendable`: state is guarded by `lock`, and the stored `NSImage`s are
/// effectively immutable once decoded here.
final class FaviconCache: @unchecked Sendable {
    static let shared = FaviconCache()

    private let lock = NSLock()
    private var images: [String: NSImage] = [:]
    /// Hosts in the order their icons were cached — the eviction order.
    private var order: [String] = []
    /// Hosts with a definitive miss (no favicon to be had) — not refetched this session.
    private var failed: Set<String> = []
    /// One shared fetch per host, awaited by every concurrent caller.
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    /// How many hosts' icons are kept before the oldest are evicted.
    private static let maxHosts = 128
    /// Favicons render at 16–64 pt; anything bigger is wasted memory.
    private static let maxPixelSize = 64

    private func host(of url: URL) -> String? { url.host?.lowercased() }

    /// The cached favicon for `url`'s host, if one has already been fetched — a
    /// synchronous lookup so `ItemView.resolveIcon` can render it immediately.
    func cached(for url: URL) -> NSImage? {
        guard let host = host(of: url) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return images[host]
    }

    /// Returns the host's favicon, fetching it if needed. Concurrent callers for the
    /// same host share a single network fetch. Returns `nil` for a miss (definitive
    /// misses are remembered for the session; transport errors are retried later).
    func fetch(for url: URL) async -> NSImage? {
        guard let host = host(of: url) else { return nil }

        let task: Task<NSImage?, Never>
        lock.lock()
        if let image = images[host] { lock.unlock(); return image }
        if failed.contains(host) { lock.unlock(); return nil }
        if let existing = inFlight[host] {
            task = existing
        } else {
            let fetch = Task<NSImage?, Never> { [weak self] in
                let outcome = await FaviconCache.download(host: host)
                self?.record(outcome, for: host)
                if case .image(let image) = outcome { return image }
                return nil
            }
            inFlight[host] = fetch
            task = fetch
        }
        lock.unlock()
        return await task.value
    }

    // MARK: Fetching

    private enum Outcome {
        case image(NSImage)
        /// The server answered and there is no usable favicon — don't ask again.
        case definitiveMiss
        /// The request itself failed (offline, timeout) — worth retrying later.
        case transportError
    }

    private static func download(host: String) async -> Outcome {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/favicon.ico"
        guard let faviconURL = components.url else { return .definitiveMiss }
        do {
            let (data, response) = try await URLSession.shared.data(from: faviconURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = downscaled(data) else { return .definitiveMiss }
            return .image(image)
        } catch {
            return .transportError
        }
    }

    /// Decodes `data` into a thumbnail no larger than `maxPixelSize` via ImageIO —
    /// thread-safe, and it drops the extra representations a multi-size ICO carries.
    private static func downscaled(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Records a finished fetch under the lock: caches the icon (evicting the oldest
    /// past the cap), pins a definitive miss, or leaves a transport error unmarked so
    /// a later fetch retries.
    private func record(_ outcome: Outcome, for host: String) {
        lock.lock(); defer { lock.unlock() }
        inFlight[host] = nil
        switch outcome {
        case .image(let image):
            if images[host] == nil { order.append(host) }
            images[host] = image
            while order.count > Self.maxHosts {
                images[order.removeFirst()] = nil
            }
        case .definitiveMiss:
            failed.insert(host)
        case .transportError:
            break
        }
    }
}
