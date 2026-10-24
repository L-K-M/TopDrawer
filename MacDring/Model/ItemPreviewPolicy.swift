import Foundation

/// What the preview panel (`ItemPreviewController`, macOS) is allowed to show, for
/// which drawer items. Pure Foundation — no AppKit/WebKit — so the rules stay
/// unit-testable on both platforms, the same seam the listers use.
///
/// Two decisions live here because both the drawer's context menus ("Quick Look" /
/// "Preview Website" items) and the controller's own navigation delegate enforce
/// them — menus decide whether to offer a preview at all, and the web preview
/// re-checks every URL the page tries to reach.
enum ItemPreviewPolicy {
    enum Frame { case main, subframe }
    private static let inertSubframeURLs: Set<String> = ["about:blank", "about:srcdoc"]

    static func allowsNavigation(to url: URL, frame: Frame) -> Bool {
        isWebsite(url) || (frame == .subframe && inertSubframeURLs.contains(url.absoluteString))
    }

    static func browserURL(original: URL, current: URL?) -> URL? {
        if let current, isWebsite(current) { return current }
        return isWebsite(original) ? original : nil
    }

    /// Whether `url` may load inside the embedded web preview.
    ///
    /// Only real web documents: `http`/`https`, a non-empty host, and **no userinfo**
    /// (`https://user:pass@host` hides a credential the preview has no business
    /// forwarding). Everything else — `file:`, `data:`, `javascript:`, `about:`,
    /// custom app schemes — is refused: a preview panel must never become a path to
    /// local files or to script running outside a real web origin.
    static func isWebsite(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil,
              let host = url.host, !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return false }
        return true
    }

    /// Whether `item` can be shown by the **file** preview: a `.file` or `.folder`
    /// whose bookmark/URL resolves to a local URL. Apps, links, groups, the Trash,
    /// volumes, and cloud roots all open in their own handlers instead (Finder, the
    /// browser, the group's own sub-grid), so they are not previewable.
    static func canPreview(_ item: DrawerItem) -> Bool {
        guard item.kind == .file || item.kind == .folder else { return false }
        guard let url = BookmarkResolver.url(for: item) else { return false }
        return url.isFileURL
    }
}
