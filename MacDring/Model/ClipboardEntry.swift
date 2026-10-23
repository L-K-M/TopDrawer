import Foundation

/// Session-only plain text. Clipboard contents never enter the launcher document.
struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date

    private static let previewLength = 160

    var preview: String {
        let prefix = text.prefix(Self.previewLength)
        return String(prefix) + (prefix.endIndex == text.endIndex ? "" : "…")
    }
}
