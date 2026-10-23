import Foundation
#if canImport(Combine)
import Combine
#endif

/// Shared by Clipboard tabs, bounded and deliberately never written to disk.
final class ClipboardHistoryStore: ObservableObject {
    static let limit = 50
    static let maximumTextBytes = 256 * 1024

    @Published private(set) var entries: [ClipboardEntry] = []

    func record(_ text: String, at date: Date = Date()) {
        guard text.utf8.count <= Self.maximumTextBytes,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Keep identity when a repeated copy moves an older entry to the front.
        let id = entries.first { $0.text == text }?.id ?? UUID()
        let entry = ClipboardEntry(id: id, text: text, date: date)
        entries = [entry] + entries.filter { $0.text != text }.prefix(Self.limit - 1)
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries = []
    }
}
