import Foundation

/// Plain text history, kept separate from the launcher document and layout exports.
struct ClipboardEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let date: Date

    private static let previewLength = 160

    var preview: String {
        let prefix = text.prefix(Self.previewLength)
        return String(prefix) + (prefix.endIndex == text.endIndex ? "" : "…")
    }
}
