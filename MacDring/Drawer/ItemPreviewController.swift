#if os(macOS)
import AppKit
import Carbon.HIToolbox   // kVK_Escape
import Quartz            // QLPreviewView
import WebKit

/// Owns the one-at-a-time preview panel the drawer opens from its context menus or
/// a Space keypress: a Quick Look (`QLPreviewView`) of a file or folder, or a
/// sandboxed `WKWebView` for a web link.
///
/// Bounded by design, matching the drawer's own rules:
/// - `.nonactivatingPanel` — the app never activates; the titled panel can still
///   become key, which is what Esc and web text entry need.
/// - `.canJoinAllSpaces / .stationary / .fullScreenAuxiliary`, like the drawer.
/// - Attached to the parent as a **child window** and detached on close — it
///   follows the drawer off-screen rather than lingering like a floating dock,
///   and the parent never retains a closed preview.
/// - No event monitors of its own; Esc arrives through the responder chain.
/// - The web view uses a non-persistent data store and every URL it may reach —
///   link clicks, redirects, scripted navigations, popups — is re-checked against
///   `ItemPreviewPolicy.isWebsite`. Downloads and credential prompts are refused.
final class ItemPreviewController: NSObject {

    /// Called once when the preview closes — via `close()`, the panel's close
    /// button, or Esc. Not called when a `show…` supersedes the current preview:
    /// from the caller's view the session simply continues with new content.
    /// The panel's state is fully torn down *before* this fires, so a callback
    /// that opens another preview (or calls `close()` again) can't disturb it.
    var onClose: (() -> Void)?
    var onOpenExternally: ((URL) -> Void)?

    /// "Open File" / "Open in Browser" go through the shared launch service, never
    /// `NSWorkspace` from the view layer (AGENTS.md's layering rule). Injectable.
    private let opener: AppLaunching

    private enum Target { case file(URL), website(URL) }
    private enum CloseReason { case dismissed, replaced }
    private enum Activity { case loading, idle }

    private weak var parent: NSWindow?
    private var panel: PreviewPanel?
    private var quickLookView: QLPreviewView?
    private var webView: WKWebView?
    /// Strong: `WKWebView`'s delegate properties are weak, so the coordinator
    /// object would drop out from under the view without this.
    private var webDelegate: WebDelegate?
    private var closeObserver: NSObjectProtocol?

    private var contentArea: NSView?
    private var spinner: NSProgressIndicator?
    private var statusLabel: NSTextField?
    private var openButton: NSButton?
    private var target: Target?
    private var isTearingDown = false
    private var navigationWasRefused = false

    init(opener: AppLaunching = SystemAppLauncher()) {
        self.opener = opener
        super.init()
    }

    // MARK: Public API

    /// Previews a local file or folder via Quick Look, attached to `parent`.
    /// Returns false (leaving nothing on screen) for non-local URLs and targets
    /// that no longer exist — the caller then shows its own "couldn't preview"
    /// message. Any current preview is superseded first.
    @discardableResult
    func showFile(_ url: URL, relativeTo parent: NSWindow) -> Bool {
        teardown(reason: .replaced)
        guard let kind = ItemActionService.previewFileKind(at: url) else { return false }
        target = .file(url)
        presentPanel(titled: url.lastPathComponent, relativeTo: parent)
        openButton?.title = kind == .folder ? "Open Folder" : "Open File"
        setStatus("Quick Look", activity: .idle)
        guard showQuickLook(url) else {
            teardown(reason: .replaced)
            return false
        }
        return true
    }

    /// Previews a web link in a sandboxed web view. Only URLs that pass
    /// `ItemPreviewPolicy.isWebsite` are accepted; anything else returns false and
    /// leaves nothing on screen.
    @discardableResult
    func showWebsite(_ url: URL, relativeTo parent: NSWindow) -> Bool {
        teardown(reason: .replaced)
        guard ItemPreviewPolicy.isWebsite(url) else { return false }
        target = .website(url)
        presentPanel(titled: url.host ?? url.absoluteString, relativeTo: parent)
        openButton?.title = "Open in Browser"
        showWebPage(url)
        return true
    }

    /// Tears the preview down: stops the web view, clears the Quick Look item,
    /// releases delegates and content, detaches the panel from its parent, and
    /// reports the close once through `onClose`. Safe to call with nothing open.
    func close() {
        teardown(reason: .dismissed)
    }

    /// Whether `window` is this controller's live preview panel — used by the
    /// drawer's click-outside handling. Nil-safe.
    func contains(_ window: NSWindow?) -> Bool {
        panel != nil && window === panel
    }

    // MARK: Teardown

    private func teardown(reason: CloseReason) {
        guard let panel, !isTearingDown else { return }
        isTearingDown = true

        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        self.panel = nil

        // Detach before ordering out so the parent never retains a closed preview.
        parent?.removeChildWindow(panel)
        parent = nil

        quickLookView?.previewItem = nil
        quickLookView?.close()
        quickLookView = nil

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        webDelegate = nil

        contentArea = nil
        spinner = nil
        statusLabel = nil
        openButton = nil
        target = nil
        onOpenExternally = nil
        navigationWasRefused = false

        // orderOut, not close(): when teardown is reached through the panel's own
        // willClose notification, the system close is already in flight.
        panel.orderOut(nil)
        panel.contentView = nil

        // Fired last: all state is already cleared, so a callback that re-enters
        // `show…` builds a new panel unaffected by this teardown.
        isTearingDown = false
        if reason == .dismissed { onClose?() }
    }

    /// The panel's own close (traffic-light button) arrives here; everything else
    /// (Esc, `close()`) drives `teardown` directly.
    private func panelWillClose() {
        guard !isTearingDown else { return }
        teardown(reason: .dismissed)
    }

    // MARK: Panel & chrome

    private static let screenMargin: CGFloat = 24
    private static let preferredContentSize = CGSize(width: 720, height: 540)
    private static let minimumContentSize = CGSize(width: 320, height: 240)
    private static let toolbarHeight: CGFloat = 34

    private func presentPanel(titled title: String, relativeTo parent: NSWindow) {
        self.parent = parent
        let panel = PreviewPanel(
            contentRect: NSRect(origin: .zero, size: Self.preferredContentSize),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = title
        // Match the drawer's panel behavior; keyboard focus follows explicit clicks.
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false   // teardown owns the panel's lifetime
        panel.isRestorable = false
        panel.contentMinSize = Self.minimumContentSize
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.onRequestClose = { [weak self] in self?.close() }

        let content = NSView(frame: NSRect(origin: .zero, size: Self.preferredContentSize))
        panel.contentView = content
        buildChrome(in: content)
        place(panel, relativeTo: parent)
        self.panel = panel

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.panelWillClose()
        }

        parent.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
        // makeKey() activates the accessory app. Leave initial keys in the drawer.
    }

    /// The toolbar strip: status + spinner on the left, Open-externally and Close
    /// on the right. Below it, `contentArea` holds the live preview view.
    private func buildChrome(in content: NSView) {
        let strip = NSVisualEffectView(frame: NSRect(
            x: 0, y: content.bounds.height - Self.toolbarHeight,
            width: content.bounds.width, height: Self.toolbarHeight))
        strip.material = .headerView
        strip.blendingMode = .withinWindow
        strip.state = .active
        strip.autoresizingMask = [.width, .minYMargin]   // pinned to the top edge

        let spinner = NSProgressIndicator(frame: NSRect(x: 10, y: 9, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.autoresizingMask = [.maxXMargin]

        let status = NSTextField(labelWithString: "")
        status.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        status.autoresizingMask = [.width]   // stretches with the strip

        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill",
                           accessibilityDescription: "Close preview") ?? NSImage(),
            target: self, action: #selector(closePressed(_:)))
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.setFrameSize(NSSize(width: 22, height: 22))
        closeButton.autoresizingMask = [.minXMargin]   // pinned right

        let openButton = NSButton(title: "Open", target: self, action: #selector(openExternally(_:)))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        openButton.sizeToFit()
        openButton.setFrameSize(NSSize(width: max(openButton.frame.width + 8, 110), height: 22))
        openButton.autoresizingMask = [.minXMargin]   // pinned right

        // Right edge: close, then open. The status label takes what remains.
        let trailing = strip.bounds.width - 10
        closeButton.frame.origin = NSPoint(x: trailing - 22, y: 6)
        openButton.frame.origin = NSPoint(x: closeButton.frame.minX - 8 - openButton.frame.width, y: 6)
        status.frame = NSRect(x: 32, y: 0,
                              width: max(60, openButton.frame.minX - 8 - 32),
                              height: Self.toolbarHeight)

        strip.addSubview(spinner)
        strip.addSubview(status)
        strip.addSubview(openButton)
        strip.addSubview(closeButton)
        content.addSubview(strip)

        let area = NSView(frame: NSRect(x: 0, y: 0, width: content.bounds.width,
                                        height: content.bounds.height - Self.toolbarHeight))
        area.autoresizingMask = [.width, .height]
        content.addSubview(area)

        self.contentArea = area
        self.spinner = spinner
        self.statusLabel = status
        self.openButton = openButton
    }

    /// Sizes the panel to fit the parent's screen and centers it on the parent,
    /// clamped fully inside `visibleFrame` — near the drawer, never off-screen.
    private func place(_ panel: NSPanel, relativeTo parent: NSWindow) {
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let margin = Self.screenMargin
        let chrome = panel.frameRect(forContentRect: .zero).size
        let available = CGSize(width: max(1, visible.width - 2 * margin - chrome.width),
                               height: max(1, visible.height - 2 * margin - chrome.height))
        panel.contentMinSize = CGSize(width: min(Self.minimumContentSize.width, available.width),
                                      height: min(Self.minimumContentSize.height, available.height))
        let content = CGSize(width: min(Self.preferredContentSize.width, available.width),
                             height: min(Self.preferredContentSize.height, available.height))
        panel.setContentSize(content)

        let size = panel.frame.size   // includes the title bar
        var origin = CGPoint(x: parent.frame.midX - size.width / 2,
                             y: parent.frame.midY - size.height / 2)
        let minX = visible.minX + margin, minY = visible.minY + margin
        origin.x = min(max(origin.x, minX), max(minX, visible.maxX - size.width - margin))
        origin.y = min(max(origin.y, minY), max(minY, visible.maxY - size.height - margin))
        panel.setFrameOrigin(origin)
    }

    /// Swaps the live preview view inside `contentArea` (one is ever installed
    /// per panel, but supersede-safety keeps the invariant explicit).
    private func installContent(_ view: NSView) {
        guard let contentArea else { return }
        contentArea.subviews.forEach { $0.removeFromSuperview() }
        view.frame = contentArea.bounds
        view.autoresizingMask = [.width, .height]
        contentArea.addSubview(view)
    }

    private func setStatus(_ text: String, activity: Activity) {
        statusLabel?.stringValue = text
        if activity == .loading { spinner?.startAnimation(nil) } else { spinner?.stopAnimation(nil) }
    }

    // MARK: Content

    private func showQuickLook(_ url: URL) -> Bool {
        guard let contentArea,
              let preview = QLPreviewView(frame: contentArea.bounds, style: .normal) else { return false }
        preview.autostarts = true
        preview.previewItem = url as NSURL   // NSURL conforms to QLPreviewItem
        quickLookView = preview
        installContent(preview)
        return true
    }

    private func showWebPage(_ url: URL) {
        guard let contentArea else { return }
        let configuration = WKWebViewConfiguration()
        // Nothing persists: a preview must not smear cookies, cache, or storage
        // into a later one.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: contentArea.bounds, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = false
        let delegate = WebDelegate(controller: self, webView: webView)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        self.webDelegate = delegate
        self.webView = webView
        installContent(webView)
        setStatus("Loading \(url.host ?? "page")…", activity: .loading)
        webView.load(URLRequest(url: url))
    }

    // MARK: Toolbar actions

    @objc private func openExternally(_ sender: Any?) {
        let url: URL
        switch target {
        case .file(let target): url = target
        case .website(let original):
            guard let current = ItemPreviewPolicy.browserURL(original: original, current: webView?.url) else { return }
            url = current
        case nil: return
        }
        if let onOpenExternally {
            close()
            onOpenExternally(url)
        } else if opener.openURL(url) {
            close()
        } else {
            setStatus("Couldn't open it in the default app.", activity: .idle)
        }
    }

    @objc private func closePressed(_ sender: Any?) {
        close()
    }

    // MARK: Web delegate callbacks

    fileprivate func owns(_ candidate: WKWebView) -> Bool { webView === candidate }

    fileprivate func webLoadingStarted() {
        navigationWasRefused = false
        setStatus("Loading…", activity: .loading)
    }

    fileprivate func webLoadingFinished(title: String?) {
        setStatus("", activity: .idle)
        if case .website = target, let title, !title.isEmpty { panel?.title = title }
    }

    fileprivate func webLoadingFailed(_ error: Error) {
        guard !navigationWasRefused else { return }
        let nsError = error as NSError
        // Our own policy cancels surface here too — don't overwrite the "blocked"
        // message with a bare "cancelled".
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        setStatus("Couldn't load this page: \(error.localizedDescription)", activity: .idle)
    }

    fileprivate func refusedNavigation() {
        navigationWasRefused = true
        setStatus("This link can't be previewed. Only web pages are allowed.", activity: .idle)
    }

    fileprivate func refusedDownload() {
        navigationWasRefused = true
        setStatus("Downloads can't be previewed.", activity: .idle)
    }

    fileprivate func refusedAuthentication() {
        navigationWasRefused = true
        setStatus("Open in Browser to authenticate.", activity: .idle)
    }
}

/// The preview window itself. Every close path (traffic-light button goes through
/// `willCloseNotification`; Esc through `cancelOperation`/`keyDown`) funnels into
/// `onRequestClose`, which the controller routes to `close()`.
private final class PreviewPanel: NSPanel {
    var onRequestClose: (() -> Void)?

    /// A titled panel may become key even while `.nonactivatingPanel` keeps the
    /// app unactivated — the web view's text entry and the drawer's Esc both need
    /// it. Never main: an accessory app has no main window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onRequestClose?()   // Esc, wherever the responder chain surfaces it
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onRequestClose?() } else { super.keyDown(with: event) }
    }
}

/// All `WKNavigationDelegate`/`WKUIDelegate` decisions for the preview's web view.
/// Held strongly by the controller (the web view's delegate properties are weak)
/// so teardown is a single release.
private final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    private weak var owner: ItemPreviewController?
    private weak var view: WKWebView?

    private var controller: ItemPreviewController? {
        guard let owner, let view, owner.owns(view) else { return nil }
        return owner
    }

    init(controller: ItemPreviewController, webView: WKWebView) {
        self.owner = controller
        self.view = webView
    }

    // MARK: Navigation policy

    /// Every navigation the page initiates — link clicks, `location.assign`, form
    /// posts, client-side redirects — is re-checked against the website policy.
    /// (Server redirects reach `decidePolicyFor navigationResponse` instead; both
    /// gates exist because neither covers the other.)
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let controller, let url = navigationAction.request.url else { return .cancel }
        let frame: ItemPreviewPolicy.Frame = navigationAction.targetFrame?.isMainFrame == false ? .subframe : .main
        guard ItemPreviewPolicy.allowsNavigation(to: url, frame: frame) else {
            controller.refusedNavigation()
            return .cancel
        }
        return .allow
    }

    /// The response gate: catches server redirects to off-policy schemes
    /// (`response.url` is the post-redirect target) and refuses anything WebKit
    /// can't render — a bounded preview never downloads.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard let controller, let url = navigationResponse.response.url else { return .cancel }
        let frame: ItemPreviewPolicy.Frame = navigationResponse.isForMainFrame ? .main : .subframe
        guard ItemPreviewPolicy.allowsNavigation(to: url, frame: frame) else {
            controller.refusedNavigation()
            return .cancel
        }
        guard navigationResponse.canShowMIMEType else {
            controller.refusedDownload()
            return .cancel
        }
        return .allow
    }

    // MARK: Loading state

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        controller?.webLoadingStarted()
    }

    /// The committed main-frame URL is the last gate a redirect can be caught at.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url, !ItemPreviewPolicy.isWebsite(url) {
            webView.stopLoading()
            controller?.refusedNavigation()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        controller?.webLoadingFinished(title: webView.title)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        controller?.webLoadingFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        controller?.webLoadingFailed(error)
    }

    /// Leave certificate validation to WebKit; credential prompts belong in a browser.
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard controller != nil else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            controller?.refusedAuthentication()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Belt-and-braces: policy never produces `.download`, but anything that still
    /// becomes one is cancelled rather than written to disk.
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.cancel()
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.cancel()
    }

    // MARK: Popups

    /// WebKit asks here for `target=_blank` and `window.open`. The preview has one
    /// view; a popup may load *into it* only when it came from an explicit link
    /// click and targets a real web page. Scripted windows and off-policy URLs
    /// are dropped — returning nil gives them no view to live in.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard controller != nil, navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              ItemPreviewPolicy.isWebsite(url) else { return nil }
        webView.load(navigationAction.request)
        return nil
    }
}
#endif
