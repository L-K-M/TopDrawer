#if os(macOS)
import AppKit

/// Keeps native link editing separate from host-controlled URL activation.
struct NotesEditorLinkInteraction {
    enum Activation { case edit, open }

    /// What the host should do with the gesture.
    enum Outcome: Equatable {
        /// ⌘-click resolved a web URL — the host opens it.
        case open(URL)
        /// A plain click landed on a link. The host parks the caret itself and must
        /// swallow the event — delivered to the text view, AppKit would open the URL.
        case placeCaret
        /// No link involved (or a follow-up click of a multi-click) — deliver normally.
        case passthrough
    }

    private struct Link {
        let range: NSRange
        let url: URL?
    }

    func activate(at insertion: Int, in storage: NSTextStorage,
                  as activation: Activation, clickCount: Int) -> Outcome {
        guard insertion >= 0, insertion <= storage.length else { return .passthrough }
        // clickCount ≥ 2 is word/line selection, not navigation — let it through.
        guard clickCount <= 1 else { return .passthrough }
        let candidates = [insertion, insertion - 1].filter { $0 >= 0 && $0 < storage.length }
        guard let link = nativeLink(at: candidates, in: storage) else { return .passthrough }

        if activation == .open, let url = link.url, NotesEditorProtocol.isWebURL(url) {
            return .open(url)
        }
        // Plain click on a link: the caller parks the caret and consumes the event.
        // Removing .link here to suppress the engine's open fallback also un-styled
        // the range until the next re-render; swallowing the event suppresses the
        // open with the attribute intact.
        return .placeCaret
    }

    private func nativeLink(at candidates: [Int], in storage: NSTextStorage) -> Link? {
        var range = NSRange()
        guard let index = candidates.first(where: {
            storage.attribute(.link, at: $0, effectiveRange: nil) != nil
        }), let value = storage.attribute(.link, at: index, effectiveRange: &range) else { return nil }

        let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        return Link(range: range, url: url)
    }
}
#endif
