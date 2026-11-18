import Foundation

/// Plain text history, kept separate from the launcher document and layout exports.
struct ClipboardEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let date: Date

    /// Internal (not private) so the tests can assert the window without a
    /// hard-coded duplicate of the constant.
    static let previewLength = 160

    var preview: String {
        let prefix = text.prefix(Self.previewLength)
        return String(prefix) + (prefix.endIndex == text.endIndex ? "" : "…")
    }

    /// A preview centered on the query match, split so the view can highlight the
    /// matched text. `leading`/`trailing` carry the ellipses that mark omitted text.
    struct Excerpt: Equatable {
        let leading: String
        let matched: String
        let trailing: String
        var text: String { leading + matched + trailing }
    }

    /// Whether `query` matches this clip. Uses the same folding as
    /// `excerpt(matching:)` so the search filter and the highlight cannot drift.
    func matches(_ query: String) -> Bool {
        firstMatchRange(for: query) != nil
    }

    /// The first occurrence of `query`, matched case- and diacritic-insensitively
    /// with the current locale — the single matching rule behind both the filter
    /// and the excerpt.
    private func firstMatchRange(for query: String) -> Range<String.Index>? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return text.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive],
                          locale: .current)
    }

    /// A window of up to `previewLength` characters around the first occurrence of
    /// `query`, matched the same way the clipboard search matches (case- and
    /// diacritic-insensitive). Falls back to `preview` for an empty query or no
    /// match, so a row always has something to show.
    func excerpt(matching query: String) -> Excerpt {
        guard let match = firstMatchRange(for: query) else {
            return Excerpt(leading: preview, matched: "", trailing: "")
        }

        let matchStart = text.distance(from: text.startIndex, to: match.lowerBound)
        let matchEnd = text.distance(from: text.startIndex, to: match.upperBound)
        let matchLength = matchEnd - matchStart
        let window = Self.previewLength
        // Center the window on the match; when the match is at least as long as the
        // window, show its first `window` characters instead.
        let start = max(0, min(matchStart - (window - min(matchLength, window)) / 2,
                              text.count - min(window, text.count)))
        let end = min(text.count, start + window)

        let leadingEnd = text.index(text.startIndex, offsetBy: max(matchStart, start))
        let matchedEnd = text.index(text.startIndex, offsetBy: min(matchEnd, end))
        let sliceStart = text.index(text.startIndex, offsetBy: start)
        let sliceEnd = text.index(text.startIndex, offsetBy: end)

        var leading = String(text[sliceStart..<leadingEnd])
        var trailing = String(text[matchedEnd..<sliceEnd])
        if start > 0 { leading = "…" + leading }
        if end < text.count { trailing += "…" }
        return Excerpt(leading: leading,
                       matched: String(text[leadingEnd..<matchedEnd]),
                       trailing: trailing)
    }
}
