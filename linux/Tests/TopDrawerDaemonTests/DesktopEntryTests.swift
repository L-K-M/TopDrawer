import XCTest
@testable import TopDrawerDaemon

#if os(Linux)
/// LP-19 acceptance: `.desktop` parser tests, including snap/flatpak-exported entries,
/// plus the scanner's dedupe/precedence and field-code stripping. All pure — temp dirs
/// for the scanner, no real launching.
final class DesktopEntryTests: XCTestCase {

    // MARK: - Parser

    func testParsesCoreFields() {
        let text = """
        [Desktop Entry]
        Type=Application
        Name=Text Editor
        Exec=gedit %U
        Icon=org.gnome.gedit
        """
        let e = DesktopEntry.parse(text, id: "org.gnome.gedit", path: URL(fileURLWithPath: "/x.desktop"))
        XCTAssertEqual(e?.name, "Text Editor")
        XCTAssertEqual(e?.exec, "gedit %U")
        XCTAssertEqual(e?.icon, "org.gnome.gedit")
        XCTAssertEqual(e?.type, "Application")
        XCTAssertEqual(e?.isShown, true)
    }

    func testOnlyTheDesktopEntryGroupIsRead() {
        // Keys under a later [Desktop Action …] group must not leak into the entry.
        let text = """
        [Desktop Entry]
        Type=Application
        Name=Files
        Exec=nautilus
        [Desktop Action new-window]
        Name=New Window
        Exec=nautilus --new-window
        """
        let e = DesktopEntry.parse(text, id: "org.gnome.Nautilus", path: URL(fileURLWithPath: "/x.desktop"))
        XCTAssertEqual(e?.name, "Files")
        XCTAssertEqual(e?.exec, "nautilus")   // not the action's Exec
    }

    func testLocalizedKeysAreIgnoredInFavourOfTheDefault() {
        let text = """
        [Desktop Entry]
        Type=Application
        Name=Weather
        Name[de]=Wetter
        Exec=weather
        """
        let e = DesktopEntry.parse(text, id: "weather", path: URL(fileURLWithPath: "/x.desktop"))
        XCTAssertEqual(e?.name, "Weather")
    }

    func testNoDisplayAndHiddenAreParsedAndSuppressDisplay() {
        let hidden = DesktopEntry.parse("[Desktop Entry]\nType=Application\nName=X\nHidden=true",
                                        id: "x", path: URL(fileURLWithPath: "/x.desktop"))
        XCTAssertEqual(hidden?.hidden, true)
        XCTAssertEqual(hidden?.isShown, false)

        let noDisplay = DesktopEntry.parse("[Desktop Entry]\nType=Application\nName=X\nNoDisplay=true",
                                           id: "x", path: URL(fileURLWithPath: "/x.desktop"))
        XCTAssertEqual(noDisplay?.noDisplay, true)
        XCTAssertEqual(noDisplay?.isShown, false)
    }

    func testNonApplicationTypeIsNotShown() {
        let link = DesktopEntry.parse("[Desktop Entry]\nType=Link\nName=Home\nURL=https://x",
                                      id: "home", path: URL(fileURLWithPath: "/x.desktop"))
        XCTAssertEqual(link?.isShown, false)
    }

    func testGarbageAndCommentsYieldNilOrEmpty() {
        XCTAssertNil(DesktopEntry.parse("no groups here\n# just a comment",
                                        id: "x", path: URL(fileURLWithPath: "/x.desktop")))
        XCTAssertNil(DesktopEntry.parse("", id: "x", path: URL(fileURLWithPath: "/x.desktop")))
    }

    func testParsesSnapAndFlatpakExportedEntries() {
        // Snap: an `env VAR=… /snap/bin/foo` Exec; Flatpak: a long `flatpak run …` Exec.
        let snap = DesktopEntry.parse("""
        [Desktop Entry]
        Type=Application
        Name=Snap Store
        Exec=env BAMF_DESKTOP_FILE_HINT=/var/lib/snapd/desktop/applications/snap-store_snap-store.desktop /snap/bin/snap-store %U
        Icon=snap-store
        """, id: "snap-store_snap-store", path: URL(fileURLWithPath: "/s.desktop"))
        XCTAssertEqual(snap?.name, "Snap Store")
        XCTAssertTrue(snap?.exec.contains("/snap/bin/snap-store") == true)
        XCTAssertEqual(snap?.isShown, true)

        let flatpak = DesktopEntry.parse("""
        [Desktop Entry]
        Type=Application
        Name=Bar
        Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 org.foo.Bar @@u %U @@
        Icon=org.foo.Bar
        """, id: "org.foo.Bar", path: URL(fileURLWithPath: "/f.desktop"))
        XCTAssertEqual(flatpak?.name, "Bar")
        XCTAssertEqual(flatpak?.isShown, true)
    }

    // MARK: - Exec field codes

    func testExecStripsFieldCodesAndExpandsURIs() {
        XCTAssertEqual(DesktopEntry.execArgv("gedit %U", uris: []), ["gedit"])
        // %u/%U keep URIs; %f/%F pass local file *paths* (per the spec).
        XCTAssertEqual(DesktopEntry.execArgv("gedit %U", uris: ["file:///a", "file:///b"]),
                       ["gedit", "file:///a", "file:///b"])
        XCTAssertEqual(DesktopEntry.execArgv("app %u", uris: ["file:///a", "file:///b"]),
                       ["app", "file:///a"])   // %u = a single URI
        XCTAssertEqual(DesktopEntry.execArgv("app %f", uris: ["file:///a", "file:///b"]),
                       ["app", "/a"])           // %f = a single local file path
        XCTAssertEqual(DesktopEntry.execArgv("app %F", uris: ["file:///a", "file:///b"]),
                       ["app", "/a", "/b"])     // %F = the file paths as separate args
        XCTAssertEqual(DesktopEntry.execArgv("app %f", uris: ["file:///tmp/a%20b.txt"]),
                       ["app", "/tmp/a b.txt"]) // %f percent-decodes the URI into a local path
        XCTAssertEqual(DesktopEntry.execArgv("app --flag %i %c %k", uris: []),
                       ["app", "--flag"])       // dropped deprecated codes
    }

    func testExecHandlesQuotingAndLiteralPercent() {
        XCTAssertEqual(DesktopEntry.execArgv("\"/opt/my app/bin\" %f", uris: ["file:///x"]),
                       ["/opt/my app/bin", "/x"])   // %f = local path
        XCTAssertEqual(DesktopEntry.execArgv("printf 100%%", uris: []), ["printf", "100%"])
    }

    func testProgramNameIsTheExecBasename() {
        let e = DesktopEntry.parse("[Desktop Entry]\nType=Application\nName=X\nExec=/usr/bin/foo-bar %U",
                                   id: "x", path: URL(fileURLWithPath: "/x.desktop"))
        XCTAssertEqual(e?.programName, "foo-bar")
    }

    // MARK: - applicationDirs

    func testApplicationDirsHonorsXDG() {
        let dirs = DesktopEntryScanner.applicationDirs(
            environment: ["XDG_DATA_HOME": "/home/a/.local/share",
                          "XDG_DATA_DIRS": "/usr/local/share:/usr/share"],
            home: URL(fileURLWithPath: "/home/a"))
        XCTAssertEqual(dirs.map(\.path), [
            "/home/a/.local/share/applications",
            "/usr/local/share/applications",
            "/usr/share/applications",
        ])
    }

    func testApplicationDirsFallsBackWhenUnset() {
        let dirs = DesktopEntryScanner.applicationDirs(environment: [:],
                                                       home: URL(fileURLWithPath: "/home/a"))
        XCTAssertEqual(dirs.first?.path, "/home/a/.local/share/applications")
        XCTAssertTrue(dirs.map(\.path).contains("/usr/share/applications"))
    }

    // MARK: - Scanner (temp-dir fixtures)

    func testScanDedupesByIDWithEarlierDirWinning() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("desk-\(UUID().uuidString)")
        let userDir = root.appendingPathComponent("user/applications")
        let sysDir = root.appendingPathComponent("sys/applications")
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sysDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Same ID in both dirs; the user copy should win.
        try "[Desktop Entry]\nType=Application\nName=User Foo\nExec=foo"
            .write(to: userDir.appendingPathComponent("foo.desktop"), atomically: true, encoding: .utf8)
        try "[Desktop Entry]\nType=Application\nName=System Foo\nExec=foo"
            .write(to: sysDir.appendingPathComponent("foo.desktop"), atomically: true, encoding: .utf8)
        // A hidden system app that must be filtered out.
        try "[Desktop Entry]\nType=Application\nName=Hidden\nExec=h\nNoDisplay=true"
            .write(to: sysDir.appendingPathComponent("hidden.desktop"), atomically: true, encoding: .utf8)

        let entries = DesktopEntryScanner.scan(dirs: [userDir, sysDir])
        XCTAssertEqual(entries.map(\.id), ["foo"])
        XCTAssertEqual(entries.first?.name, "User Foo")
    }

    func testScanDerivesIDFromSubdirectoryPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("desk-\(UUID().uuidString)")
        let appsDir = root.appendingPathComponent("applications")
        let sub = appsDir.appendingPathComponent("org/gnome")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "[Desktop Entry]\nType=Application\nName=Nested\nExec=n"
            .write(to: sub.appendingPathComponent("Foo.desktop"), atomically: true, encoding: .utf8)

        let entries = DesktopEntryScanner.scan(dirs: [appsDir])
        // path relative to applications/ with `/` → `-`: org/gnome/Foo.desktop → org-gnome-Foo
        XCTAssertEqual(entries.map(\.id), ["org-gnome-Foo"])
    }

    func testEntryForIDIncludesNoDisplayHandlers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("desk-\(UUID().uuidString)")
        let appsDir = root.appendingPathComponent("applications")
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "[Desktop Entry]\nType=Application\nName=Handler\nExec=h %U\nNoDisplay=true"
            .write(to: appsDir.appendingPathComponent("handler.desktop"), atomically: true, encoding: .utf8)

        // scan() drops it (NoDisplay), but an explicit open-with target resolves.
        XCTAssertTrue(DesktopEntryScanner.scan(dirs: [appsDir]).isEmpty)
        let entry = DesktopEntryScanner.entry(forID: "handler", in: [appsDir])
        XCTAssertEqual(entry?.name, "Handler")
        XCTAssertEqual(entry?.path.lastPathComponent, "handler.desktop")
    }

    func testUserHiddenOverrideMasksTheSystemEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("desk-\(UUID().uuidString)")
        let userDir = root.appendingPathComponent("user/applications")
        let sysDir = root.appendingPathComponent("sys/applications")
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sysDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // The freedesktop way to hide an app: copy it into the user dir with Hidden=true.
        try "[Desktop Entry]\nType=Application\nName=Foo\nExec=foo\nHidden=true"
            .write(to: userDir.appendingPathComponent("foo.desktop"), atomically: true, encoding: .utf8)
        try "[Desktop Entry]\nType=Application\nName=Foo\nExec=foo"
            .write(to: sysDir.appendingPathComponent("foo.desktop"), atomically: true, encoding: .utf8)

        // The user override must MASK the system copy, not fall through to it — in both the
        // listing (scan) and the resolve/launch path (entry(forID:)).
        XCTAssertTrue(DesktopEntryScanner.scan(dirs: [userDir, sysDir]).isEmpty,
                      "a Hidden user override hides the system app entirely")
        XCTAssertNil(DesktopEntryScanner.entry(forID: "foo", in: [userDir, sysDir]),
                     "a Hidden override also masks the id for resolution, so a stale pin can't launch it")
    }

    func testEntryForIDFallsThroughWhenUserOverrideIsCorrupt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("desk-\(UUID().uuidString)")
        let userDir = root.appendingPathComponent("user/applications")
        let sysDir = root.appendingPathComponent("sys/applications")
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sysDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A readable-but-unparseable user file (no [Desktop Entry] group) must not fail the
        // lookup — the valid system copy should still resolve.
        try "garbage, not a desktop file"
            .write(to: userDir.appendingPathComponent("foo.desktop"), atomically: true, encoding: .utf8)
        try "[Desktop Entry]\nType=Application\nName=System Foo\nExec=foo"
            .write(to: sysDir.appendingPathComponent("foo.desktop"), atomically: true, encoding: .utf8)

        let entry = DesktopEntryScanner.entry(forID: "foo", in: [userDir, sysDir])
        XCTAssertEqual(entry?.name, "System Foo")
    }

    func testDesktopFileIDStripsOnlyTheTrailingSuffix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("desk-\(UUID().uuidString)")
        let appsDir = root.appendingPathComponent("applications")
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A basename that itself contains ".desktop" — only the final suffix must be trimmed.
        try "[Desktop Entry]\nType=Application\nName=Odd\nExec=odd"
            .write(to: appsDir.appendingPathComponent("com.foo.desktop.desktop"),
                   atomically: true, encoding: .utf8)

        XCTAssertEqual(DesktopEntryScanner.scan(dirs: [appsDir]).map(\.id), ["com.foo.desktop"])
    }
}
#endif
