#if os(macOS)
import SwiftUI
import WebKit

/// The notes tab's editor: the bundled web editor in a `WKWebView`.
///
/// The view is deliberately inert. All of the decisions about *when* the editor
/// is told about a document live in `NotesEditorHostSession`, and all of the wire
/// format lives in `NotesEditorBridge`, so this type is only the AppKit glue:
/// build the web view once, pump queued messages, route callbacks.
///
/// `NSViewRepresentable` is the right shape because the drawer's view is
/// re-evaluated whenever its model changes — which happens constantly for
/// unrelated reasons — and a representable keeps the same `WKWebView` across
/// those passes instead of rebuilding it.
struct NotesEditorWebView: NSViewRepresentable {

    /// Identity of the note being edited. A change means a different document.
    let documentID: UUID?
    /// The note's text as the host knows it: the store's copy, or the last text
    /// the editor reported. The reconciler decides whether it needs sending.
    let markdown: String
    let theme: NotesEditorTheme
    let onChanged: (String) -> Void
    let onOpenLink: (URL) -> Void
    /// Registers (and, with `nil`, unregisters) a way to ask the editor for a
    /// pending edit right away: the drawer close and termination paths need it,
    /// because a hidden web view does not reliably produce a visibility change.
    let registerFlush: (((() -> Void)?) -> Void)?

    func makeCoordinator() -> NotesEditorCoordinator {
        NotesEditorCoordinator(onChanged: onChanged, onOpenLink: onOpenLink, registerFlush: registerFlush)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(documentID: documentID, markdown: markdown, theme: theme)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: NotesEditorCoordinator) {
        coordinator.tearDown()
    }
}

/// Owns the web view and translates between it and the host-side reconciler.
final class NotesEditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    private let session = NotesEditorHostSession()
    private let onChanged: (String) -> Void
    private let onOpenLink: (URL) -> Void
    private let registerFlush: (((() -> Void)?) -> Void)?
    private var webView: WKWebView?

    init(onChanged: @escaping (String) -> Void,
         onOpenLink: @escaping (URL) -> Void,
         registerFlush: (((() -> Void)?) -> Void)? = nil) {
        self.onChanged = onChanged
        self.onOpenLink = onOpenLink
        self.registerFlush = registerFlush
        super.init()
    }

    // MARK: Web view lifecycle

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // No cookie jar, cache or local storage to leave behind: a note is a note,
        // and the editor stores nothing of its own.
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let handler = NotesEditorMessageProxy(delegate: self)
        configuration.userContentController.add(handler,
                                                name: NotesEditorProtocol.messageHandlerName)

        if let directory = NotesEditorSchemeHandler.bundledDirectory() {
            configuration.setURLSchemeHandler(NotesEditorSchemeHandler(directory: directory),
                                              forURLScheme: NotesEditorProtocol.scheme)
        } else {
            // The bundled assets are missing (the "Copy EditorWeb assets" build phase
            // did not run, or the app was assembled by hand). Say so once, loudly,
            // rather than presenting an empty drawer with no explanation.
            let expected = NotesEditorProtocol.assets.sorted().joined(separator: ", ")
            NSLog("Notes editor: \(expected) are missing from the app bundle's resources, "
                  + "so the notes editor cannot load. In a source checkout, run "
                  + "`cd EditorWeb && npm run build` and rebuild.")
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        // Force-touch/force-click previews fetch the linked page inside the web view,
        // which would put a network request where the app promises none.
        webView.allowsLinkPreview = false
        // The drawer is a vibrancy panel; a white page background would flash over it
        // while the editor loads. Public API (macOS 12+), not the private
        // `drawsBackground` key.
        webView.underPageBackgroundColor = .clear
        self.webView = webView
        // The drawer may hide at any moment; give it a way to ask for a pending edit.
        registerFlush?(flushPendingEdit)

        if let url = NotesEditorProtocol.pageURL {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    /// Reconciles the editor with what the drawer wants shown. Called on every
    /// SwiftUI update pass, so it must be cheap and must not re-send unchanged
    /// state — see `NotesEditorHostSession`.
    func update(documentID: UUID?, markdown: String, theme: NotesEditorTheme) {
        session.setDesired(documentID: documentID, markdown: markdown, theme: theme)
        pump()
    }

    /// Asks the editor to report a pending edit now. Called by the drawer as it
    /// hides: a hidden web view does not reliably produce a visibility change, and
    /// the alternative is losing the last few hundred milliseconds of typing.
    func flushPendingEdit() {
        guard let webView, let message = session.flushMessage() else { return }
        evaluate(message, on: webView)
    }

    /// Tears the editor down. Called from `dismantleNSView`, i.e. when the drawer
    /// stops showing a notes tab or the app goes away.
    func tearDown() {
        flushPendingEdit()
        registerFlush?(nil)   // never hold the web view (or this coordinator) past teardown
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: NotesEditorProtocol.messageHandlerName)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }

    // MARK: Sending

    /// Sends every message the reconciler has queued, in order.
    private func pump() {
        guard let webView else { return }
        while let message = session.nextMessage() {
            evaluate(message, on: webView)
        }
    }

    private func evaluate(_ message: NotesEditorHostMessage, on webView: WKWebView) {
        do {
            webView.evaluateJavaScript(try message.javaScriptInvocation())
        } catch {
            NSLog("Notes editor: could not encode \(message) (\(error))")
        }
    }

    // MARK: Receiving

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let event = NotesEditorEvent(scriptMessageBody: message.body) else {
            NSLog("Notes editor: discarded an unrecognised message (\(message.body))")
            return
        }
        handle(event)
    }

    private func handle(_ event: NotesEditorEvent) {
        switch event {
        case let .ready(protocolVersion):
            if protocolVersion != NotesEditorProtocol.version {
                // Both halves ship in the same bundle, so a mismatch means the
                // bundled assets are stale rather than an older app version.
                NSLog("Notes editor: protocol \(protocolVersion) != host \(NotesEditorProtocol.version); "
                      + "the bundled EditorWeb assets are out of date.")
            }
            session.markReady()
            pump()

        case let .changed(markdown, _):
            session.recordEditorChange(markdown)
            onChanged(markdown)

        case let .openLink(url):
            guard let url = URL(string: url) else { return }
            onOpenLink(url)

        case .focusChanged:
            // The editor flushes its own pending edit on blur; nothing to mirror.
            break

        case let .diagnostic(code, detail):
            NSLog("Notes editor diagnostic: \(code)\(detail.map { " — \($0)" } ?? "")")
        }
    }

    // MARK: Navigation

    /// The editor never navigates itself, and nothing else may steer the web view:
    /// a link becomes a host callback (opened in the user's browser), anything
    /// else is refused. Without this a stray anchor click could replace the
    /// editor with a web page inside the drawer.
    ///
    /// The async form of the delegate method, which is the one macOS 12+ calls:
    /// the completion-handler version is deprecated at this deployment target.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if NotesEditorProtocol.isEditorURL(url) { return .allow }

        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            onOpenLink(url)
        }
        return .cancel
    }
}
#endif
