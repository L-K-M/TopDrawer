#if os(Linux)
import Foundation

/// A parsed freedesktop `.desktop` entry (the `[Desktop Entry]` group only).
///
/// The daemon reads these to enumerate installed applications (for open-with and the
/// running-apps heuristic). It's a small hand-rolled parser rather than a dependency:
/// the format is a stable INI-like `key=value` grammar, and the weak-model doctrine
/// prefers parsing text over pulling GIO's `GDesktopAppInfo` through C interop.
public struct DesktopEntry: Sendable, Equatable {
    /// The desktop-file ID — the path relative to the `applications/` root with `/`
    /// replaced by `-` and the `.desktop` suffix removed (e.g. `org.gnome.Files`,
    /// `sub/Foo.desktop` → `sub-Foo`). This is what `gtk-launch` takes and what a
    /// systemd `app-<id>.scope` embeds.
    public let id: String
    public let name: String
    public let exec: String
    public let icon: String
    /// The `Type` value (`Application`, `Link`, `Directory`); apps we launch are `Application`.
    public let type: String
    public let noDisplay: Bool
    public let hidden: Bool
    public let tryExec: String
    /// The file this entry was parsed from.
    public let path: URL

    /// Whether this entry should surface to the user: an `Application` that is neither
    /// `NoDisplay` nor `Hidden` (the two freedesktop "don't show me" flags).
    public var isShown: Bool { type == "Application" && !noDisplay && !hidden }

    /// The launch program — the first `Exec` token with any field code stripped, reduced
    /// to its basename. Used to match `/proc` `comm`/`cmdline` in the running-apps scan.
    public var programName: String? {
        guard let first = Self.execArgv(exec, uris: []).first, !first.isEmpty else { return nil }
        return (first as NSString).lastPathComponent
    }

    /// Parse the `[Desktop Entry]` group out of a `.desktop` file's text. Later groups
    /// (`[Desktop Action …]`) and localized keys (`Name[de]=…`) are ignored — only the
    /// default (unlocalized) keys in the first `[Desktop Entry]` group are read. Returns
    /// `nil` if there is no `[Desktop Entry]` group at all.
    public static func parse(_ text: String, id: String, path: URL) -> DesktopEntry? {
        var inGroup = false
        var values: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                // A new group header. We only care about the first [Desktop Entry] group;
                // once we've been in it and hit another header, we're done.
                if inGroup { break }
                inGroup = (line == "[Desktop Entry]")
                continue
            }
            guard inGroup, let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            // Skip localized keys (`Name[de]`): we serve the C-locale default.
            if key.contains("[") { continue }
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if values[key] == nil { values[key] = value }
        }
        // A non-empty dictionary means we entered the [Desktop Entry] group and read at
        // least one key; an empty one means the group was absent (or had no keys).
        guard !values.isEmpty else { return nil }
        return DesktopEntry(
            id: id,
            name: values["Name"] ?? id,
            exec: values["Exec"] ?? "",
            icon: values["Icon"] ?? "",
            type: values["Type"] ?? "Application",
            noDisplay: parseBool(values["NoDisplay"]),
            hidden: parseBool(values["Hidden"]),
            tryExec: values["TryExec"] ?? "",
            path: path)
    }

    private static func parseBool(_ s: String?) -> Bool { s == "true" }

    /// Split an `Exec` string into argv, stripping the freedesktop field codes. `%f %F %u
    /// %U` are replaced by the given `uris` (file/URL arguments); the deprecated/we-don't-
    /// supply codes (`%i %c %k %d %D %n %N %v %m`) are dropped; `%%` becomes a literal `%`.
    /// Quoting follows the spec's reserved-character rule: double quotes group a token and
    /// `\"` escapes a quote inside one.
    public static func execArgv(_ exec: String, uris: [String]) -> [String] {
        var tokens: [String] = []
        var current = ""
        var haveToken = false
        var inQuote = false
        let chars = Array(exec)
        var i = 0
        func flush() {
            if haveToken { tokens.append(current); current = ""; haveToken = false }
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {                       // toggle quoting; an empty "" is still a token
                inQuote.toggle(); haveToken = true; i += 1; continue
            }
            if inQuote {
                if c == "\\", i + 1 < chars.count {   // \" \\ \$ \` inside quotes
                    current.append(chars[i + 1]); haveToken = true; i += 2; continue
                }
                current.append(c); haveToken = true; i += 1; continue
            }
            if c == " " || c == "\t" {           // argument separator outside quotes
                flush(); i += 1; continue
            }
            if c == "%", i + 1 < chars.count {   // a field code
                let code = chars[i + 1]
                i += 2
                switch code {
                // Per the spec, %f/%F are local file *paths*; %u/%U are URIs.
                case "f":
                    if let first = uris.first { current.append(Self.localPath(first)); haveToken = true }
                case "u":
                    if let first = uris.first { current.append(first); haveToken = true }
                case "F":                        // the whole list → separate args
                    flush(); tokens.append(contentsOf: uris.map(Self.localPath))
                case "U":
                    flush(); tokens.append(contentsOf: uris)
                case "%":
                    current.append("%"); haveToken = true
                default:
                    break                         // drop %i %c %k %d %D %n %N %v %m and unknowns
                }
                continue
            }
            current.append(c); haveToken = true; i += 1
        }
        flush()
        return tokens
    }

    /// A `%f`/`%F` argument is a local file *path*, not a URI: convert a `file://` URI to its
    /// (percent-decoded) filesystem path; leave anything else unchanged.
    private static func localPath(_ uri: String) -> String {
        if let url = URL(string: uri), url.isFileURL { return url.path }
        return uri
    }
}

/// Enumerates installed `.desktop` entries across the XDG application directories.
public enum DesktopEntryScanner {

    /// The ordered `applications/` directories to search, most-preferred first:
    /// `$XDG_DATA_HOME/applications` then each `$XDG_DATA_DIRS` entry's `applications/`.
    /// XDG defaults are applied when the variables are unset or empty.
    public static func applicationDirs(environment: [String: String],
                                       home: URL) -> [URL] {
        var dirs: [URL] = []
        let dataHome: URL
        if let xdh = environment["XDG_DATA_HOME"], xdh.hasPrefix("/") {
            dataHome = URL(fileURLWithPath: xdh)
        } else {
            dataHome = home.appendingPathComponent(".local/share")
        }
        dirs.append(dataHome.appendingPathComponent("applications"))

        let rawDataDirs = environment["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "/usr/local/share:/usr/share"
        for part in rawDataDirs.split(separator: ":") where part.hasPrefix("/") {
            dirs.append(URL(fileURLWithPath: String(part)).appendingPathComponent("applications"))
        }
        return dirs
    }

    /// Scan `dirs` for shown application entries, deduped by desktop-file ID with earlier
    /// directories winning (XDG precedence: a user override in `$XDG_DATA_HOME` shadows the
    /// system copy). `NoDisplay`/`Hidden`/non-`Application` entries are dropped. Sorted by
    /// display name for a stable order.
    public static func scan(dirs: [URL],
                            fileManager: FileManager = .default) -> [DesktopEntry] {
        var byID: [String: DesktopEntry] = [:]
        var resolved = Set<String>()
        for dir in dirs {
            for (id, fileURL) in desktopFiles(in: dir, fileManager: fileManager) {
                guard !resolved.contains(id) else { continue }   // first *parseable* file wins
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
                      let entry = DesktopEntry.parse(text, id: id, path: fileURL) else { continue }
                resolved.insert(id)
                // A Hidden/NoDisplay entry in a higher-precedence dir masks the id entirely
                // — a user copy with `Hidden=true` hides the system app, per freedesktop
                // semantics — so record the id but don't surface it (an unreadable/corrupt
                // file leaves the id unresolved so a lower copy can still win).
                guard entry.isShown else { continue }
                byID[id] = entry
            }
        }
        return byID.values.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    /// Resolve a single entry by its desktop-file ID, searching `dirs` in precedence order.
    /// Unlike `scan`, this does not filter on `isShown` — an explicit open-with target may
    /// legitimately be a `NoDisplay` handler.
    public static func entry(forID id: String, in dirs: [URL],
                             fileManager: FileManager = .default) -> DesktopEntry? {
        for dir in dirs {
            for (candidateID, fileURL) in desktopFiles(in: dir, fileManager: fileManager)
            where candidateID == id {
                // Only act on a successful parse, so a corrupt higher-precedence override
                // falls through to a valid system copy rather than failing the lookup.
                if let text = try? String(contentsOf: fileURL, encoding: .utf8),
                   let entry = DesktopEntry.parse(text, id: id, path: fileURL) {
                    // A `Hidden=true` override means the user removed the app: mask the id
                    // here too (consistent with `scan`), so a stale pin can't launch it. A
                    // `NoDisplay` entry is still resolvable — it's a legitimate (menu-hidden)
                    // handler — so gate on `hidden` only, not the full `isShown`.
                    guard !entry.hidden else { return nil }
                    return entry
                }
            }
        }
        return nil
    }

    /// Every `*.desktop` file under `dir` (recursively), paired with its desktop-file ID
    /// (path relative to `dir`, `/` → `-`, `.desktop` removed).
    static func desktopFiles(in dir: URL, fileManager: FileManager) -> [(id: String, url: URL)] {
        guard let enumerator = fileManager.enumerator(
            at: dir, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles], errorHandler: nil) else { return [] }
        var out: [(String, URL)] = []
        let base = dir.standardizedFileURL.path
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "desktop" {
            let full = fileURL.standardizedFileURL.path
            guard full.hasPrefix(base + "/") else { continue }
            let relative = String(full.dropFirst(base.count + 1))
            // Drop only the trailing `.desktop` (the `pathExtension` filter guarantees it),
            // not every occurrence — a subdir or basename containing ".desktop" must survive.
            let id = relative.replacingOccurrences(of: "/", with: "-").dropLast(".desktop".count)
            out.append((String(id), fileURL))
        }
        return out
    }
}
#endif
