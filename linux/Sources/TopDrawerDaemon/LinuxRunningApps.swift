#if os(Linux)
import Foundation

/// Extracts the desktop-file id of a running application from the name of its systemd user
/// scope. Stock GNOME (and other systemd sessions) launch each app into a transient scope
/// named `app[-<launcher>]-<ApplicationID>[-<PID>|@<RANDOM>].scope`, where the id's own
/// dashes are escaped as `\x2d`. This is the "`/proc` + `.desktop` matching" fallback the
/// port targets for the stock-GNOME tier (Shell introspection is allow-listed away).
public enum RunningAppScope {

    /// Launcher prefixes that the launching process puts before the application id in the
    /// scope name it asks systemd to create. The two seen on stock GNOME: GNOME Shell emits
    /// `gnome-`, and GLib's `GDesktopAppInfo` (behind `gio launch` / `gtk-launch`, and so
    /// behind this daemon's own `Launch`/`OpenWith`) tags its scopes
    /// `app-glib-<id>-<pid>.scope` whenever the app isn't started by GNOME Shell.
    private static let launchers = ["gnome-", "glib-", "flatpak-", "kde-", "snap-"]

    /// The desktop-file id embedded in a scope unit name, or `nil` if `scope` isn't an
    /// `app-*.scope`. E.g. `app-gnome-org.gnome.Nautilus-2468.scope` → `org.gnome.Nautilus`.
    public static func desktopID(fromScopeName scope: String) -> String? {
        guard scope.hasPrefix("app-"), scope.hasSuffix(".scope") else { return nil }
        var core = String(scope.dropFirst("app-".count).dropLast(".scope".count))

        // Drop a leading launcher segment (`app-<launcher>-<id>-<pid>`).
        for launcher in launchers where core.hasPrefix(launcher) {
            core = String(core.dropFirst(launcher.count)); break
        }

        // Strip the trailing instance token. Two forms: `@<random>` (systemd template
        // instances) or `-<pid>`. The id's own dashes are `\x2d`-escaped, so a *literal*
        // trailing `-` always separates the id from the pid.
        if let at = core.firstIndex(of: "@") {
            core = String(core[..<at])
        } else if let dash = core.lastIndex(of: "-") {
            core = String(core[..<dash])
        }

        // Unescape systemd's `\x2d` back to the literal dash the id actually uses.
        core = core.replacingOccurrences(of: "\\x2d", with: "-")
        return core.isEmpty ? nil : core
    }

    /// The `app-*.scope` id named anywhere in a `/proc/<pid>/cgroup` file's contents, if any.
    /// The cgroup path components are `/`-separated; the scope is the leaf.
    static func desktopID(inCgroup content: String) -> String? {
        for token in content.split(whereSeparator: { $0 == "/" || $0 == "\n" || $0 == ":" })
        where token.hasPrefix("app-") && token.hasSuffix(".scope") {
            if let id = desktopID(fromScopeName: String(token)) { return id }
        }
        return nil
    }
}

/// The daemon's source of running-application ids. `ProcRunningApps` reads `/proc` in
/// production; a fake drives the D-Bus tests deterministically.
public protocol RunningAppsScanning: Sendable {
    /// The desktop-file ids of currently-running apps, de-duplicated and sorted.
    func runningAppIDs() -> [String]
}

/// Scans `/proc/<pid>/cgroup` for `app-*.scope` membership — the boring, inotify-free
/// heuristic the weak-model doctrine prefers over Shell introspection or systemd D-Bus.
public struct ProcRunningApps: RunningAppsScanning {
    private let procRoot: URL

    /// - Parameter procRoot: the `/proc` mount to scan; injectable so tests use a fixture.
    public init(procRoot: URL = URL(fileURLWithPath: "/proc")) { self.procRoot = procRoot }

    public func runningAppIDs() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: procRoot.path) else { return [] }
        var ids = Set<String>()
        // ASCII-numeric entries are process directories; skip `self`, `sys`, etc.
        // `Character.isNumber` also accepts non-ASCII numerals (e.g. `٣`, `²`), so gate on
        // ASCII to match what a real `/proc` (and the guard's intent) actually holds.
        for pid in entries where !pid.isEmpty && pid.allSatisfy({ $0.isASCII && $0.isNumber }) {
            let cgroup = procRoot.appendingPathComponent(pid, isDirectory: true)
                .appendingPathComponent("cgroup")
            guard let content = try? String(contentsOf: cgroup, encoding: .utf8) else { continue }
            if let id = RunningAppScope.desktopID(inCgroup: content) { ids.insert(id) }
        }
        return ids.sorted()
    }
}
#endif
