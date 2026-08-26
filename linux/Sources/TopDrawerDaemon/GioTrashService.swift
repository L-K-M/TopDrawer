import Foundation
import MacDring

/// The freedesktop Trash location: `$XDG_DATA_HOME/Trash` (with `$XDG_DATA_HOME`
/// defaulting to `~/.local/share`). Split out and cross-platform so the count logic is
/// unit-testable against a temp directory on either CI.
public enum TrashLocation {
    /// The home Trash directory (`…/Trash`). Its `files/` subdirectory holds the trashed
    /// items; `info/` holds the restore metadata.
    public static func directory(environment: [String: String],
                                 home: URL) -> URL {
        let base: URL
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = home.appendingPathComponent(".local/share", isDirectory: true)
        }
        return base.appendingPathComponent("Trash", isDirectory: true)
    }

    /// The number of trashed items — the immediate entries under `Trash/files`, which is
    /// what freedesktop "Empty Trash" clears. Pure over an injected trash directory.
    public static func count(trashDirectory: URL, fileManager: FileManager = .default) -> Int {
        let files = trashDirectory.appendingPathComponent("files", isDirectory: true)
        let entries = try? fileManager.contentsOfDirectory(
            at: files, includingPropertiesForKeys: nil, options: [])
        return entries?.count ?? 0
    }
}

#if os(Linux)
/// `MacDring.TrashServicing` (LP-12) for Linux: counts the freedesktop home Trash and
/// drives it through `gio` (from `libglib2.0-bin`), the desktop-neutral tool every
/// GNOME/KDE session ships. `gio trash` files into the correct `.Trash` for each file's
/// volume and writes the restore metadata, so trashing stays recoverable.
public struct GioTrashService: TrashServicing {
    private let fileManager = FileManager.default

    public init() {}

    private var trashDirectory: URL {
        TrashLocation.directory(environment: ProcessInfo.processInfo.environment,
                                home: fileManager.homeDirectoryForCurrentUser)
    }

    public func trashCount() -> Int {
        TrashLocation.count(trashDirectory: trashDirectory, fileManager: fileManager)
    }

    public func trashIsEmpty() -> Bool { trashCount() == 0 }

    public func trash(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return true }
        // One invocation per file so a single unmovable file doesn't sink the rest, and
        // the aggregate result reflects whether *all* succeeded (matches macOS).
        return urls.reduce(true) { ok, url in
            LinuxProcess.succeeds("gio", ["trash", url.path]) && ok
        }
    }

    public func emptyTrash() -> Bool {
        LinuxProcess.succeeds("gio", ["trash", "--empty"])
    }
}
#endif
