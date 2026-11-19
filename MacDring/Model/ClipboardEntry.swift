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

    /// A clip that matched the clipboard search, with the excerpt its row shows.
    struct SearchResult: Identifiable {
        let entry: ClipboardEntry
        let excerpt: Excerpt
        var id: UUID { entry.id }
    }

    /// This clip as a search result, or `nil` when `query` doesn't match. A blank
    /// query matches every clip with the plain preview. The filter and the
    /// highlight share this one scan, so they cannot drift apart, and the row
    /// never searches the text again.
    func searchResult(for query: String) -> SearchResult? {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SearchResult(entry: self, excerpt: plainExcerpt)
        }
        guard let match = firstMatchRange(for: query) else { return nil }
        return SearchResult(entry: self, excerpt: excerpt(around: match))
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
        firstMatchRange(for: query).map(excerpt(around:)) ?? plainExcerpt
    }

    private var plainExcerpt: Excerpt { Excerpt(leading: preview, matched: "", trailing: "") }

    /// Centers the window on the match; when the match is at least as long as the
    /// window, shows its first `previewLength` characters instead. Room one side
    /// can't use goes to the other. Every walk starts at the match and is bounded
    /// by the window, so the cost doesn't grow with the clip's length (a clip can
    /// be 256 KiB).
    private func excerpt(around match: Range<String.Index>) -> Excerpt {
        let window = Self.previewLength
        // Offsetting by zero rounds a bound inside a grapheme (a diacritic-folded
        // match can end in one) down to a Character boundary.
        let matchStart = text.index(match.lowerBound, offsetBy: 0)
        let matchEnd = text.index(match.upperBound, offsetBy: 0)
        let matchedEnd = text.index(matchStart, offsetBy: window, limitedBy: matchEnd) ?? matchEnd
        let spare = window - text.distance(from: matchStart, to: matchedEnd)

        var sliceStart = text.index(matchStart, offsetBy: -(spare / 2), limitedBy: text.startIndex)
            ?? text.startIndex
        let wantedAfter = spare - text.distance(from: sliceStart, to: matchStart)
        let sliceEnd = text.index(matchedEnd, offsetBy: wantedAfter, limitedBy: text.endIndex)
            ?? text.endIndex
        let unusedAfter = wantedAfter - text.distance(from: matchedEnd, to: sliceEnd)
        if unusedAfter > 0 {
            sliceStart = text.index(sliceStart, offsetBy: -unusedAfter, limitedBy: text.startIndex)
                ?? text.startIndex
        }

        var leading = String(text[sliceStart..<matchStart])
        var trailing = String(text[matchedEnd..<sliceEnd])
        if sliceStart > text.startIndex { leading = "…" + leading }
        if sliceEnd < text.endIndex { trailing += "…" }
        return Excerpt(leading: leading, matched: String(text[matchStart..<matchedEnd]),
                       trailing: trailing)
    }
}

/// Decodes a single `ClipboardEntry` without throwing: an unreadable element yields
/// `nil` (and is skipped) rather than failing the whole `[ClipboardEntry]` decode,
/// which would hide every entry and stop saving until the user cleared the history.
/// The same pattern as `FailableRecentItem`.
struct FailableClipboardEntry: Decodable {
    let entry: ClipboardEntry?

    init(from decoder: Decoder) throws {
        entry = try? ClipboardEntry(from: decoder)
    }
}
