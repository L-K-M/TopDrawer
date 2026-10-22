#if os(macOS)
import AppKit

/// Keeps native link editing separate from host-controlled URL activation.
struct NotesEditorLinkInteraction {
    enum Activation { case edit, open }

    private struct Link {
        let range: NSRange
        let url: URL?
        let text: String
    }

    private var editingLink: Link?

    mutating func activate(at insertion: Int, in storage: NSTextStorage,
                           as activation: Activation) -> URL? {
        guard insertion >= 0, insertion <= storage.length else { return nil }
        let text = storage.string
        // Canonically equivalent strings can still move UTF-16 link ranges.
        if let editingLink, !editingLink.text.utf16.elementsEqual(text.utf16) {
            self.editingLink = nil
        }

        let candidates = [insertion, insertion - 1].filter { $0 >= 0 && $0 < storage.length }
        let native = nativeLink(at: candidates, in: storage, text: text)
        let cached = editingLink.flatMap { link in
            candidates.contains { NSLocationInRange($0, link.range) } ? link : nil
        }
        guard let link = native ?? cached else { return nil }

        // Preserve activation while the engine reveals editable source. Never
        // restore old attributes asynchronously: an intervening edit can move them.
        editingLink = link
        if activation == .open, let url = link.url, NotesEditorProtocol.isWebURL(url) { return url }

        // Keep native selection, suppressing the engine's plain-click URL fallback.
        storage.removeAttribute(.link, range: link.range)
        return nil
    }

    private func nativeLink(at candidates: [Int], in storage: NSTextStorage, text: String) -> Link? {
        var range = NSRange()
        guard let index = candidates.first(where: {
            storage.attribute(.link, at: $0, effectiveRange: nil) != nil
        }), let value = storage.attribute(.link, at: index, effectiveRange: &range) else { return nil }

        let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        return Link(range: range, url: url, text: text)
    }
}
#endif
