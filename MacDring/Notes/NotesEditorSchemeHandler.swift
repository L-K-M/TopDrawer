#if os(macOS)
import Foundation
import WebKit

/// Serves the bundled editor to the web view over `topdrawer-editor://`.
///
/// A custom scheme rather than `loadFileURL(_:allowingReadAccessTo:)` for two
/// reasons. The page's CSP says `script-src 'self'`, and 'self' needs a document
/// origin that its own subresources match — a file-URL document may not have one,
/// while every request here shares `topdrawer-editor://editor`. And the web
/// content gets no file-system reach at all: it can ask for the three names in
/// `NotesEditorProtocol.assets` and nothing else, whatever path it invents.
///
/// This serves synchronously on the main thread, which is why there is no
/// bookkeeping for stopped tasks: `start` cannot be interleaved with `stop`, so
/// no task can be answered after it was cancelled.
final class NotesEditorSchemeHandler: NSObject, WKURLSchemeHandler {

    /// Directory holding the three assets, normally `EditorWeb/` in the app's
    /// resources (filled by the "Copy EditorWeb assets" build phase).
    private let directory: URL

    /// MIME types for the served names. WebKit needs a real type: it applies the
    /// page's CSP to the response, and an octet-stream script is refused.
    private static let mimeTypes: [String: String] = [
        "editor.html": "text/html",
        "editor.js": "text/javascript",
        "editor.css": "text/css",
    ]

    init(directory: URL) {
        self.directory = directory
    }

    /// The bundled asset directory for the app, or `nil` when the build phase did
    /// not run — a missing editor is then a visible diagnostic instead of a crash.
    static func bundledDirectory(in bundle: Bundle = .main) -> URL? {
        guard let resources = bundle.resourceURL else { return nil }
        let directory = resources.appendingPathComponent("EditorWeb", isDirectory: true)
        return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let asset = NotesEditorProtocol.assetName(for: url) else {
            // Not one of ours: refuse rather than fall through to the file system.
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }

        let fileURL = directory.appendingPathComponent(asset)
        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(url: url,
                                   mimeType: Self.mimeTypes[asset] ?? "application/octet-stream",
                                   expectedContentLength: data.count,
                                   textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to cancel: every response is written before this can be called.
    }
}
#endif
