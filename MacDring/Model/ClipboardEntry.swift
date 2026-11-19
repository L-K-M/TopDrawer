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
