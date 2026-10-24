import Foundation

/// Downloads a release asset into the user's Downloads folder, picking a
/// non-colliding filename. Reusable across apps — depends only on Foundation.
struct UpdateDownloader {
    enum DownloadError: LocalizedError {
        case nonHTTPSURL(URL)
        case invalidResponse
        case badResponse(Int)
        case fileSizeUnavailable
        case sizeMismatch(expected: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case .nonHTTPSURL:
                return "The update asset URL must use HTTPS."
            case .invalidResponse:
                return "The update download returned an invalid response."
            case .badResponse(let code):
                return "The update download returned HTTP \(code)."
            case .fileSizeUnavailable:
                return "Couldn't determine the downloaded update's file size."
            case .sizeMismatch(let expected, let actual):
                return "The downloaded update has an unexpected size (expected \(expected) bytes, got \(actual) bytes)."
            }
        }
    }

    var session: any UpdateDownloadSession = URLSession.shared
    var fileManager: FileManager = .default

    /// Downloads `asset` to `~/Downloads`, returning the saved file URL.
    func downloadToDownloads(_ asset: GitHubRelease.Asset) async throws -> URL {
        guard asset.browserDownloadURL.scheme?.lowercased() == "https" else {
            throw DownloadError.nonHTTPSURL(asset.browserDownloadURL)
        }

        let (tempURL, response) = try await session.downloadAsset(from: asset.browserDownloadURL)
        var shouldRemoveTemp = true
        defer {
            if shouldRemoveTemp {
                try? fileManager.removeItem(at: tempURL)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.badResponse(http.statusCode)
        }
        if asset.size > 0 {
            let attributes = try fileManager.attributesOfItem(atPath: tempURL.path)
            guard let actualSize = (attributes[.size] as? NSNumber)?.intValue else {
                throw DownloadError.fileSizeUnavailable
            }
            guard actualSize == asset.size else {
                throw DownloadError.sizeMismatch(expected: asset.size, actual: actualSize)
            }
        }

        let downloads = try fileManager.url(for: .downloadsDirectory, in: .userDomainMask,
                                            appropriateFor: nil, create: true)
        let destination = Self.uniqueDestination(in: downloads, fileName: asset.name, fileManager: fileManager)
        try fileManager.moveItem(at: tempURL, to: destination)
        shouldRemoveTemp = false
        Self.applyQuarantine(to: destination)
        return destination
    }

    /// Tags the download with `com.apple.quarantine`, the same flag a browser
    /// download carries — URLSession does not set it itself. Without it a tampered
    /// release payload would open with no Gatekeeper evaluation; with it macOS
    /// runs its notarization/signature check on first open, same as any browser
    /// download. Failure is non-fatal: the file is still a normal download.
    static func applyQuarantine(to url: URL, agentName: String = "TopDrawer") {
        #if os(macOS)
        // Flags 0x0081: quarantined + Gatekeeper "lethal" checks pending — the
        // value browsers stamp on potentially executable payloads.
        let value = "0081;\(String(UInt64(Date().timeIntervalSince1970), radix: 16));\(agentName);\(UUID().uuidString)"
        setxattr(url.path, "com.apple.quarantine", value, value.utf8.count, 0, 0)
        #endif
    }

    /// A non-colliding URL in `directory` for `fileName` (`Foo.dmg`, then `Foo-1.dmg`,
    /// `Foo-2.dmg`, …) so re-downloading never clobbers an existing file.
    static func uniqueDestination(in directory: URL, fileName: String,
                                  fileManager: FileManager = .default) -> URL {
        let name = sanitizedFileName(fileName)
        let first = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: first.path) else { return first }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 1
        while true {
            let candidateName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private static func sanitizedFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmed as NSString).lastPathComponent
        // `lastPathComponent` collapses an all-separator name (e.g. "///") to "/",
        // which would otherwise resolve back to the directory itself.
        if name.isEmpty || name == "." || name == ".." || name == "/" { return "download" }
        return name
    }
}
