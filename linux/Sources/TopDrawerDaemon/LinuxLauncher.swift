#if os(Linux)
import Foundation

/// Runs a CLI tool to completion, reporting success (exit 0). Injectable so the launcher's
/// command construction is unit-testable without spawning real processes.
public protocol CommandRunning: Sendable {
    func run(_ tool: String, _ args: [String]) -> Bool
}

/// Production runner: shells out via `LinuxProcess` (which resolves the tool on `PATH`).
public struct SystemCommandRunner: CommandRunning {
    public init() {}
    public func run(_ tool: String, _ args: [String]) -> Bool {
        LinuxProcess.succeeds(tool, args)
    }
}

/// The daemon's launch seam — the Linux equivalent of MacDring's `AppLaunching`, but
/// operating on the raw values the daemon already has (a `LauncherItem`, a desktop-file ID,
/// a URI) so no `DrawerItem`/`AppLaunching` type needs to become public. Injected into
/// `TopDrawerService` so the D-Bus handler tests can fake it.
public protocol LinuxLaunching: Sendable {
    /// Open an item: applications launch their `.desktop`/handler, everything else opens in
    /// its default handler. Returns whether the launch was dispatched.
    func launch(_ item: LauncherItem) -> Bool
    /// Open `uris` *with* a specific application (drop-onto-app / "Open With"), named by its
    /// desktop-file ID.
    func openWith(desktopID: String, uris: [String]) -> Bool
    /// Reveal `uri` in the file manager (select it in its folder).
    func reveal(uri: String) -> Bool
}

/// `LinuxLaunching` via the desktop-neutral CLIs the weak-model doctrine prefers over C
/// interop: `gio` (from `libglib2.0-bin`, on every GNOME/KDE session) with `xdg-open`
/// fallbacks, and `gdbus` for the file-manager reveal.
public struct LinuxLauncher: LinuxLaunching {
    private let runner: CommandRunning
    private let applicationDirs: [URL]

    public init(runner: CommandRunning = SystemCommandRunner(),
                applicationDirs: [URL]? = nil) {
        self.runner = runner
        self.applicationDirs = applicationDirs
            ?? DesktopEntryScanner.applicationDirs(
                environment: ProcessInfo.processInfo.environment,
                home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public func launch(_ item: LauncherItem) -> Bool {
        guard let target = item.url, !target.isEmpty else { return false }
        // An application whose target is a .desktop file launches through it; a plain
        // executable/desktop-id falls through to `gio open` (which resolves default
        // handlers). Everything else (file/folder/url/disk/cloud) opens in its default app.
        if item.kind == "application", target.hasSuffix(".desktop") {
            let path = URL(string: target)?.path ?? target
            return runner.run("gio", ["launch", path])
        }
        return open(uri: target)
    }

    public func openWith(desktopID: String, uris: [String]) -> Bool {
        let id = desktopID.hasSuffix(".desktop") ? String(desktopID.dropLast(".desktop".count)) : desktopID
        // The plan's prescription is `gio launch <desktop-file> <files>`, so resolve the ID
        // to its .desktop path first. If the entry isn't installed, let `gtk-launch` try to
        // resolve the bare ID itself as a last resort.
        if let entry = DesktopEntryScanner.entry(forID: id, in: applicationDirs) {
            return runner.run("gio", ["launch", entry.path.path] + uris)
        }
        return runner.run("gtk-launch", [id] + uris)
    }

    public func reveal(uri: String) -> Bool {
        // The freedesktop file-manager interface selects the item inside its folder.
        let showItems = runner.run("gdbus", [
            "call", "--session",
            "--dest", "org.freedesktop.FileManager1",
            "--object-path", "/org/freedesktop/FileManager1",
            "--method", "org.freedesktop.FileManager1.ShowItems",
            "['\(uri)']", "",
        ])
        if showItems { return true }
        // Fallback: just open the parent directory (no selection).
        guard let url = URL(string: uri), url.isFileURL else { return false }
        return open(uri: url.deletingLastPathComponent().absoluteString)
    }

    /// `gio open <uri>` with an `xdg-open` fallback — both resolve the default handler.
    private func open(uri: String) -> Bool {
        runner.run("gio", ["open", uri]) || runner.run("xdg-open", [uri])
    }
}
#endif
