import XCTest
@testable import TopDrawerDaemon

#if os(Linux)
/// LP-19 acceptance: "launch calls mocked". A recording `CommandRunning` captures the exact
/// CLI invocations the launcher builds, so no real `gio`/`gtk-launch`/`gdbus` runs.
final class LinuxLauncherTests: XCTestCase {

    /// Records every `run` and returns a scripted success/failure per tool.
    final class RecordingRunner: CommandRunning, @unchecked Sendable {
        struct Call: Equatable { let tool: String; let args: [String] }
        private let lock = NSLock()
        private var _calls: [Call] = []
        /// Tools that should report success; anything else returns false.
        private let succeedTools: Set<String>

        init(succeed: Set<String>) { self.succeedTools = succeed }

        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

        func run(_ tool: String, _ args: [String]) -> Bool {
            lock.lock(); _calls.append(Call(tool: tool, args: args)); lock.unlock()
            return succeedTools.contains(tool)
        }
    }

    private func item(kind: String, url: String?) -> LauncherItem {
        LauncherItem(id: "x", kind: kind, name: "X", url: url)
    }

    // MARK: - launch

    func testLaunchOpensAFileViaGioOpen() {
        let runner = RecordingRunner(succeed: ["gio"])
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [])
        XCTAssertTrue(launcher.launch(item(kind: "file", url: "file:///home/a/x.pdf")))
        XCTAssertEqual(runner.calls, [.init(tool: "gio", args: ["open", "file:///home/a/x.pdf"])])
    }

    func testLaunchFallsBackToXdgOpenWhenGioFails() {
        let runner = RecordingRunner(succeed: ["xdg-open"])
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [])
        XCTAssertTrue(launcher.launch(item(kind: "folder", url: "file:///home/a")))
        XCTAssertEqual(runner.calls, [
            .init(tool: "gio", args: ["open", "file:///home/a"]),
            .init(tool: "xdg-open", args: ["file:///home/a"]),
        ])
    }

    func testLaunchApplicationDesktopFileUsesGioLaunch() {
        let runner = RecordingRunner(succeed: ["gio"])
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [])
        let ok = launcher.launch(item(kind: "application",
                                      url: "file:///usr/share/applications/gedit.desktop"))
        XCTAssertTrue(ok)
        XCTAssertEqual(runner.calls, [.init(tool: "gio", args: ["launch", "/usr/share/applications/gedit.desktop"])])
    }

    func testLaunchWithNoURLFails() {
        let runner = RecordingRunner(succeed: ["gio", "xdg-open"])
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [])
        XCTAssertFalse(launcher.launch(item(kind: "file", url: nil)))
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testLaunchApplicationByBareDesktopIDResolvesViaScanner() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bl-\(UUID().uuidString)")
        let appsDir = root.appendingPathComponent("applications")
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let desktop = appsDir.appendingPathComponent("org.gnome.calc.desktop")
        try "[Desktop Entry]\nType=Application\nName=Calc\nExec=gnome-calculator"
            .write(to: desktop, atomically: true, encoding: .utf8)

        let runner = RecordingRunner(succeed: ["gio"])
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [appsDir])
        // A bare desktop-file id (has the suffix, no slash) resolves to the installed entry.
        XCTAssertTrue(launcher.launch(item(kind: "application", url: "org.gnome.calc.desktop")))
        XCTAssertEqual(runner.calls, [.init(tool: "gio", args: ["launch", desktop.path])])
    }

    // MARK: - openWith

    func testOpenWithResolvesDesktopFileAndUsesGioLaunch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-\(UUID().uuidString)")
        let appsDir = root.appendingPathComponent("applications")
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let desktop = appsDir.appendingPathComponent("org.gnome.gedit.desktop")
        try "[Desktop Entry]\nType=Application\nName=Editor\nExec=gedit %U"
            .write(to: desktop, atomically: true, encoding: .utf8)

        let runner = RecordingRunner(succeed: ["gio"])
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [appsDir])
        let ok = launcher.openWith(desktopID: "org.gnome.gedit",
                                   uris: ["file:///a", "file:///b"])
        XCTAssertTrue(ok)
        XCTAssertEqual(runner.calls, [
            .init(tool: "gio", args: ["launch", desktop.path, "file:///a", "file:///b"]),
        ])
    }

    func testOpenWithFallsBackToGtkLaunchWhenEntryIsMissing() {
        let runner = RecordingRunner(succeed: ["gtk-launch"])
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [])
        // A trailing ".desktop" on the id is tolerated.
        let ok = launcher.openWith(desktopID: "com.unknown.App.desktop", uris: ["file:///a"])
        XCTAssertTrue(ok)
        XCTAssertEqual(runner.calls, [.init(tool: "gtk-launch", args: ["com.unknown.App", "file:///a"])])
    }

    // MARK: - reveal

    func testRevealUsesFileManagerDBus() {
        let runner = RecordingRunner(succeed: ["gdbus"])
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [])
        XCTAssertTrue(launcher.reveal(uri: "file:///home/a/x.pdf"))
        XCTAssertEqual(runner.calls.first?.tool, "gdbus")
        XCTAssertEqual(runner.calls.first?.args.last(where: { $0.contains("file://") }),
                       "['file:///home/a/x.pdf']")
    }

    func testRevealFallsBackToOpeningTheParentDirectory() {
        let runner = RecordingRunner(succeed: ["gio"])   // gdbus fails, gio open succeeds
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [])
        XCTAssertTrue(launcher.reveal(uri: "file:///home/a/x.pdf"))
        XCTAssertEqual(runner.calls.first?.tool, "gdbus")
        // Fallback opens the parent directory.
        XCTAssertEqual(runner.calls.last, .init(tool: "gio", args: ["open", "file:///home/a/"]))
    }

    func testRevealEscapesQuotesForGVariant() {
        let runner = RecordingRunner(succeed: ["gdbus"])
        let launcher = LinuxLauncher(runner: runner, applicationDirs: [])
        // An apostrophe in the filename must be backslash-escaped, not terminate the string.
        XCTAssertTrue(launcher.reveal(uri: "file:///tmp/don't.txt"))
        XCTAssertEqual(runner.calls.first?.args.last(where: { $0.contains("file://") }),
                       #"['file:///tmp/don\'t.txt']"#)
    }
}
#endif
