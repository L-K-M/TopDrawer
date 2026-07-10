import Foundation

protocol UpdateDownloadSession {
    func downloadAsset(from url: URL) async throws -> (URL, URLResponse)
}

extension URLSession: UpdateDownloadSession {
    func downloadAsset(from url: URL) async throws -> (URL, URLResponse) {
        try await download(from: url)
    }
}
