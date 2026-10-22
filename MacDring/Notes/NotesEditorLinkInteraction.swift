#if os(macOS)
import AppKit

/// Keeps native link editing separate from host-controlled URL activation.
struct NotesEditorLinkInteraction {
    enum Activation { case edit, open }

    mutating func activate(at insertion: Int, in storage: NSTextStorage,
                           as activation: Activation) -> URL? {
        let candidates = [insertion, insertion - 1].filter { $0 >= 0 && $0 < storage.length }
        var range = NSRange()
        guard let index = candidates.first(where: {
            storage.attribute(.link, at: $0, effectiveRange: nil) != nil
        }), let value = storage.attribute(.link, at: index, effectiveRange: &range) else { return nil }

        let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        if activation == .open, let url, NotesEditorProtocol.isWebURL(url) { return url }

        // The engine otherwise opens URLs on plain clicks after mouse tracking.
        storage.removeAttribute(.link, range: range)
        return nil
    }
}
#endif
