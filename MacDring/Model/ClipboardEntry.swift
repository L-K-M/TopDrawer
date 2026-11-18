import Foundation

/// Plain text history, kept separate from the launcher document and layout exports.
struct ClipboardEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let date: Date

    private static let previewLength = 160

    var preview: String {
        preview(startingAt: text.startIndex)
    }

    private func preview(startingAt start: String.Index) -> String {
        let excerpt = text[start...].prefix(Self.previewLength)
        let leading = start == text.startIndex ? "" : "…"
        let trailing = excerpt.endIndex == text.endIndex ? "" : "…"
        return leading + excerpt + trailing
    }

    struct SearchResult: Identifiable {
        let entry: ClipboardEntry
        fileprivate let excerptStart: String.Index

        var id: UUID { entry.id }
        var preview: String { entry.preview(startingAt: excerptStart) }
    }

    /// Begin at the first match so even a two-line row shows why it was found.
    func searchResult(for query: String) -> SearchResult? {
        if query.isEmpty { return SearchResult(entry: self, excerptStart: text.startIndex) }
        guard let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive],
                                     locale: .current) else { return nil }
        let start = text.rangeOfComposedCharacterSequences(for: match).lowerBound
        return SearchResult(entry: self, excerptStart: start)
    }
}
