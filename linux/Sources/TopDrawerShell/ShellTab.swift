#if os(Linux)
import Foundation

/// One tab of the launcher document, as the shell's dock strip needs it: identity and
/// a label. The daemon serves the document JSON verbatim (`GetDocument`), so the
/// client parses it the same tolerant way the daemon's `LauncherTabs` does — raw
/// `JSONSerialization` lookups, no model dependency on MacDring (whose `TabStore`
/// types stay module-internal).
public struct ShellTab: Sendable, Equatable {

    public let id: String
    /// The tab's display title; falls back to the id when the document omits `title`
    /// (a dock pill always needs *some* label).
    public let title: String
    /// The tab kind raw value (`items`, `recents`, `fresh`, …) — LP-21 picks glyph and
    /// shape from it; LP-20 only logs it.
    public let kind: String

    public init(id: String, title: String, kind: String) {
        self.id = id
        self.title = title
        self.kind = kind
    }

    /// Every tab in a launcher-document JSON, in document order. Tolerant: a malformed
    /// or empty document yields `[]` (the strip shows its placeholder), and a tab
    /// without an `id` is skipped — an id is the address every later interaction
    /// (clicks, drops, hotkeys) keys on.
    public static func parse(_ json: String) -> [ShellTab] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tabs = root["tabs"] as? [[String: Any]] else { return [] }

        return tabs.compactMap { tab in
            guard let id = tab["id"] as? String, !id.isEmpty else { return nil }
            let title = (tab["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            return ShellTab(id: id,
                            title: title,
                            kind: tab["kind"] as? String ?? "items")
        }
    }
}
#endif
