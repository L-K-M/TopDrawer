import Foundation

/// Moves dropped files into a directory (the Finder-style "file it here" action),
/// renaming to avoid collisions. Used when a file is dropped onto a folder item
/// or a folder tab.
enum FileMover {
    /// A completed move, for undo: the file went from `from` to `to`.
    struct Move: Equatable { let from: URL; let to: URL }

    @discardableResult
    static func move(_ urls: [URL], into directory: URL) -> Bool {
        movingFiles(urls, into: directory).allSucceeded
    }

    /// Moves files into `directory` and returns the completed `from → to` pairs (so a
    /// caller can offer an Undo) plus whether every move succeeded.
    static func movingFiles(_ urls: [URL], into directory: URL,
                            fileManager: FileManager = .default) -> (moves: [Move], allSucceeded: Bool) {
        var moves: [Move] = []
        var allSucceeded = true
        for url in urls {
            // A file dropped into the directory it already lives in is a no-op
            // (e.g. dragging a folder tab's own item a few pixels and releasing
            // it back inside the drawer). Without this guard, `uniqueDestination`
            // — which only ever returns a path that does *not* exist — would step
            // past the source itself and silently rename it to "name 2".
            if url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
                continue
            }
            let destination = uniqueDestination(for: url, in: directory, fileManager: fileManager)
            do {
                try fileManager.moveItem(at: url, to: destination)
                moves.append(Move(from: url, to: destination))
            } catch {
                allSucceeded = false
                NSLog("Top Drawer: couldn't move \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (moves, allSucceeded)
    }

    /// Reverses completed moves (best-effort), putting each file back where it came
    /// from. Returns whether every reversal succeeded.
    @discardableResult
    static func undo(_ moves: [Move], fileManager: FileManager = .default) -> Bool {
        var allSucceeded = true
        for move in moves.reversed() {
            do {
                try fileManager.createDirectory(at: move.from.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try fileManager.moveItem(at: move.to, to: move.from)
            } catch {
                allSucceeded = false
                NSLog("Top Drawer: couldn't undo move of \(move.to.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return allSucceeded
    }

    /// Moves dropped files to the Trash (recoverable — `trashItem`, not a hard
    /// delete). Used when files are dropped onto a Trash item.
    @discardableResult
    static func trash(_ urls: [URL],
                      trashItem: (URL) throws -> Void = { url in
                          try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                      }) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }

        var allSucceeded = true
        for url in fileURLs {
            do {
                try trashItem(url)
            } catch {
                allSucceeded = false
                NSLog("Top Drawer: couldn't trash \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return allSucceeded
    }

    /// Empties the Trash by asking Finder via Apple Events — the only way without
    /// Full Disk Access, since the Trash is privacy-protected. Requires the
    /// `com.apple.security.automation.apple-events` entitlement; macOS prompts the
    /// user once to allow controlling Finder. Returns false if the event was
    /// blocked (e.g. the user declined) or Finder reported an error. Main thread.
    @discardableResult
    static func emptyTrash() -> Bool {
        guard let script = NSAppleScript(source: #"tell application "Finder" to empty the trash"#) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            NSLog("Top Drawer: couldn't empty the Trash: \(error)")
            return false
        }
        return true
    }

    /// A non-colliding destination in `directory` for `url` (appends " 2", " 3", …).
    static func uniqueDestination(for url: URL, in directory: URL, fileManager: FileManager = .default) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = directory.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }
}
