import Foundation

/// The wire protocol between the app and the bundled notes editor.
///
/// This mirrors `EditorWeb/src/bridge.ts`, which is the authority for the field
/// names and the semantics; the two must move together, and the editor reports
/// its `protocolVersion` on `ready` so a mismatch is visible rather than silent.
/// Everything here is Foundation-only so the Linux job compiles and tests it
/// alongside the macOS one — the messages are the part of the integration that
/// can be verified without a web view.
enum NotesEditorProtocol {

    /// The version this host speaks. Any change to the message shapes bumps it.
    static let version = 1

    /// Name of the `WKScriptMessageHandler` the page posts to
    /// (`window.webkit.messageHandlers.topdrawer`), which is also the name
    /// WebKitGTK exposes to JavaScript.
    static let messageHandlerName = "topdrawer"

    /// The global the page installs to receive host messages. Fully qualified: the
    /// host evaluates statements in the page's context, where a bare `topdrawerEditor`
    /// happens to resolve as a global property today, but that is an accident of
    /// classic scripts rather than something to rely on.
    static let editorGlobalName = "window.topdrawerEditor"

    /// Custom scheme the app serves the editor from. A real origin is what makes
    /// `script-src 'self'` meaningful in the page's CSP and keeps the web view
    /// from having any file-system reach of its own.
    static let scheme = "topdrawer-editor"

    /// Host component of the editor's origin (`topdrawer-editor://editor/…`).
    static let host = "editor"

    /// The page the host loads, relative to the origin above.
    static let pagePath = "/editor.html"

    /// Every asset the page may request, by name. The scheme handler serves this
    /// list and nothing else, so a stray reference cannot reach the bundle.
    static let assets: Set<String> = ["editor.html", "editor.js", "editor.css"]

    /// What the editor calls this host. It uses the value only to reason about
    /// keyboard conventions; the app passes `macos`.
    static let platform = "macos"

    /// The page URL a web view should load.
    static var pageURL: URL? { URL(string: "\(scheme)://\(host)\(pagePath)") }

    /// Whether `url` is the editor's own page or one of its assets.
    static func isEditorURL(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == host
    }

    /// The asset name a request is for, or `nil` when it is not one we serve.
    static func assetName(for url: URL) -> String? {
        guard isEditorURL(url) else { return nil }
        let name = url.lastPathComponent
        return assets.contains(name) ? name : nil
    }
}

/// A message the host sends into the web view.
///
/// Encoded as JSON, then embedded in one `evaluateJavaScript` call. See
/// `javaScriptInvocation(_:)` for why the second encoding step matters.
enum NotesEditorHostMessage: Equatable {
    /// Loads a document and resets the editor's change tracking to `revision`.
    case initialize(markdown: String, theme: String, revision: Int)
    /// Replaces the document under a fresh revision (an edit made outside the
    /// editor, e.g. by the other drawer or a device sync).
    case replaceDocument(markdown: String, revision: Int)
    case setTheme(theme: String)
    case focus
    /// Asks the editor to report any pending edit right away. The drawer close
    /// path uses this, because hiding a web view does not reliably produce a
    /// visibility change.
    case flush
    case command(name: String)

    /// The JSON object for this message. `[String: Any]` is the shape
    /// `JSONSerialization` needs; the editor validates it on arrival.
    var jsonObject: [String: Any] {
        switch self {
        case let .initialize(markdown, theme, revision):
            return ["type": "initialize", "markdown": markdown, "theme": theme,
                    "platform": NotesEditorProtocol.platform, "revision": revision]
        case let .replaceDocument(markdown, revision):
            return ["type": "replaceDocument", "markdown": markdown, "revision": revision]
        case let .setTheme(theme):
            return ["type": "setTheme", "theme": theme]
        case .focus:
            return ["type": "focus"]
        case .flush:
            return ["type": "flush"]
        case let .command(name):
            return ["type": "command", "name": name]
        }
    }

    /// The message as a JSON string.
    func jsonString() throws -> String {
        // `.fragmentsAllowed` because a bare string is not a JSON document: without
        // it, serialising the payload's string form throws.
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        return String(decoding: data, as: UTF8.self)
    }

    /// A single JavaScript statement that delivers this message to the page.
    ///
    /// The JSON is embedded as a *JavaScript string literal*, so it is
    /// JSON-encoded twice: once for the payload, once for the literal. Passing
    /// the payload unescaped would let a note containing a quote, a backslash or
    /// a line separator end the string and run as code — and the U+2028/U+2029
    /// cases are escaped by hand because JSON leaves them raw while a JavaScript
    /// parser has historically treated them as line terminators.
    func javaScriptInvocation() throws -> String {
        let json = try jsonString()
        // `.fragmentsAllowed` here is what makes the *string* a valid top-level JSON
        // document, so its quotes and backslashes come back escaped as a JS literal.
        let literalData = try JSONSerialization.data(withJSONObject: json,
                                                     options: [.fragmentsAllowed])
        let literal = String(decoding: literalData, as: UTF8.self)
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "\(NotesEditorProtocol.editorGlobalName).handleMessage(\(literal))"
    }
}

/// Something the editor told the host.
enum NotesEditorEvent: Equatable {
    case ready(protocolVersion: Int)
    /// A local edit. `editorRevision` is the editor's own counter, for
    /// diagnostics only; the host tracks its own revision for documents it sends.
    case changed(markdown: String, editorRevision: Int)
    case openLink(url: String)
    case focusChanged(isFocused: Bool)
    /// The editor refused or could not do something. Surfaced for logging.
    case diagnostic(code: String, detail: String?)
}

extension NotesEditorEvent {

    /// Decodes a `WKScriptMessage.body`: a JSON object the page posted.
    ///
    /// Returns `nil` for anything that is not a well-formed message this host
    /// understands. Unknown *types* are rejected rather than ignored: the page
    /// and the host ship together inside the app bundle, so an unrecognised
    /// message means they disagree, and silently dropping it would hide that.
    init?(scriptMessageBody body: Any) {
        guard let object = body as? [String: Any], let type = object["type"] as? String else {
            return nil
        }
        switch type {
        case "ready":
            self = .ready(protocolVersion: Self.int(object["protocolVersion"]) ?? 0)
        case "changed":
            guard let markdown = object["markdown"] as? String else { return nil }
            self = .changed(markdown: markdown, editorRevision: Self.int(object["editorRevision"]) ?? 0)
        case "openLink":
            guard let url = object["url"] as? String else { return nil }
            self = .openLink(url: url)
        case "focusChanged":
            guard let focused = Self.bool(object["isFocused"]) else { return nil }
            self = .focusChanged(isFocused: focused)
        case "diagnostic":
            guard let code = object["code"] as? String else { return nil }
            self = .diagnostic(code: code, detail: object["detail"] as? String)
        default:
            return nil
        }
    }

    /// Numbers arrive as `NSNumber` from WebKit (JSONSerialization) and as Swift
    /// integers in tests, and the two bridge differently on Linux, so accept both
    /// spellings rather than assuming one platform's behaviour.
    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        return (value as? NSNumber)?.intValue
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        return (value as? NSNumber)?.boolValue
    }
}
