import Foundation
#if canImport(Combine)
import Combine
#endif

/// Shared, bounded text history with opt-in storage outside the launcher document.
final class ClipboardHistoryStore: ObservableObject {
    enum Retention { case sessionOnly, acrossRestarts }

    static let limit = 50
    static let maximumTextBytes = 256 * 1024
    // JSON can escape one text byte as six bytes; allow space for entry metadata.
    private static let maximumArchiveBytes = limit * maximumTextBytes * 6 + 16 * 1024
    private static let saveDelay: TimeInterval = 0.3
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var persistenceError: String?

    private let storeURL: URL
    private var retention: Retention
    private var saveWorkItem: DispatchWorkItem?
    private var canSave = true

    init(storeURL: URL? = nil, retention: Retention = .sessionOnly) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        self.storeURL = storeURL ?? base.appendingPathComponent("MacDring/Clipboard/history.json")
        self.retention = retention

        if retention == .acrossRestarts {
            load()
        } else {
            discardSavedHistory()
        }
    }

    deinit { saveWorkItem?.cancel() }

    /// Disabling retention deletes the archive but keeps the current session usable.
    func setRetention(_ retention: Retention) {
        guard self.retention != retention else { return }
        self.retention = retention
        canSave = true
        saveNow()
    }

    func record(_ text: String, at date: Date = Date()) {
        guard Self.isValid(text) else { return }

        // Keep identity when a repeated copy moves an older entry to the front.
        let id = entries.first { $0.text == text }?.id ?? UUID()
        let entry = ClipboardEntry(id: id, text: text, date: date)
        entries = [entry] + entries.filter { $0.text != text }.prefix(Self.limit - 1)
        scheduleSave()
    }

    func remove(id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        saveNow()
    }

    func clear() {
        if !entries.isEmpty { entries = [] }
        canSave = true
        saveNow()
    }

    /// Flush before dropping memory; quitting must not persist an empty history.
    func finishSession() {
        saveNow()
        entries = []
    }

    // MARK: Persistence

    private static func isValid(_ text: String) -> Bool {
        text.utf8.count <= maximumTextBytes
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scheduleSave() {
        guard retention == .acrossRestarts else { return }
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// Called on quit and after privacy-sensitive removals, without a backup copy.
    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard retention == .acrossRestarts else {
            discardSavedHistory()
            return
        }
        guard canSave else { return }
        guard !entries.isEmpty else {
            discardSavedHistory()
            return
        }

        do {
            let directory = storeURL.deletingLastPathComponent()
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: Self.directoryPermissions])
            // The private directory also protects atomic-write temporary files.
            try manager.setAttributes([.posixPermissions: Self.directoryPermissions], ofItemAtPath: directory.path)
            try JSONEncoder().encode(entries).write(to: storeURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: Self.filePermissions], ofItemAtPath: storeURL.path)
            persistenceError = nil
        } catch {
            persistenceError = "Couldn't save clipboard history. Check free space and Application Support permissions."
        }
    }

    private func discardSavedHistory() {
        do {
            try FileManager.default.removeItem(at: storeURL)
            persistenceError = nil
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            persistenceError = nil
        } catch {
            persistenceError = "Couldn't delete saved clipboard history. Check Application Support permissions."
        }
    }

    private func load() {
        do {
            let file = try FileHandle(forReadingFrom: storeURL)
            defer { try? file.close() }
            let data = try file.read(upToCount: Self.maximumArchiveBytes + 1) ?? Data()
            guard data.count <= Self.maximumArchiveBytes else {
                throw CocoaError(.fileReadTooLarge)
            }
            let decoded = try JSONDecoder().decode([ClipboardEntry].self, from: data)
            var texts = Set<String>()
            var ids = Set<UUID>()
            var restored: [ClipboardEntry] = []
            for entry in decoded {
                guard restored.count < Self.limit else { break }
                guard Self.isValid(entry.text), !texts.contains(entry.text), !ids.contains(entry.id) else { continue }
                texts.insert(entry.text)
                ids.insert(entry.id)
                restored.append(entry)
            }
            entries = restored
        } catch let error as CocoaError
            where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // Darwin FileHandle and corelibs Foundation use different missing-file codes.
            return
        } catch {
            // Preserve an unreadable archive until the user explicitly clears it.
            canSave = false
            persistenceError = "Couldn't restore clipboard history. Clear history to start a new archive."
        }
    }
}
