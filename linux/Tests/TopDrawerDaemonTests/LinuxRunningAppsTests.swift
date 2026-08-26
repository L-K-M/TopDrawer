import XCTest
@testable import TopDrawerDaemon

#if os(Linux)
/// LP-19b acceptance: scope-name → desktop-id parsing (incl. flatpak/snap/`@`-instance and
/// dash-escaped forms) and the `/proc` scan over a temp fixture. Pure — no real `/proc`.
final class LinuxRunningAppsTests: XCTestCase {

    // MARK: - Scope name parsing

    func testParsesGnomeScopeName() {
        XCTAssertEqual(RunningAppScope.desktopID(fromScopeName: "app-gnome-org.gnome.Nautilus-2468.scope"),
                       "org.gnome.Nautilus")
    }

    func testParsesGlibScopeName() {
        // GLib's GDesktopAppInfo (behind `gio launch`/`gtk-launch`, so behind the daemon's
        // own Launch/OpenWith) tags scopes `app-glib-<id>-<pid>.scope` — the most common
        // launch path on stock GNOME.
        XCTAssertEqual(RunningAppScope.desktopID(fromScopeName: "app-glib-org.gnome.Calculator-4321.scope"),
                       "org.gnome.Calculator")
    }

    func testParsesFlatpakScopeName() {
        XCTAssertEqual(RunningAppScope.desktopID(fromScopeName: "app-flatpak-com.example.App-4812.scope"),
                       "com.example.App")
    }

    func testParsesScopeWithNoLauncherSegment() {
        XCTAssertEqual(RunningAppScope.desktopID(fromScopeName: "app-org.kde.dolphin-1234.scope"),
                       "org.kde.dolphin")
    }

    func testParsesAtInstanceScopeName() {
        XCTAssertEqual(RunningAppScope.desktopID(fromScopeName: "app-gnome-org.gnome.Console@d3adb33f.scope"),
                       "org.gnome.Console")
    }

    func testUnescapesDashesInID() {
        // systemd escapes a literal `-` in the id as `\x2d`.
        XCTAssertEqual(RunningAppScope.desktopID(fromScopeName: "app-gnome-foo\\x2dbar-999.scope"),
                       "foo-bar")
    }

    func testParsesSnapExportedScopeName() {
        // Snap ids look like `snap-store_snap-store`; the dashes are `\x2d`-escaped in the scope.
        XCTAssertEqual(
            RunningAppScope.desktopID(fromScopeName: "app-snap-snap\\x2dstore_snap\\x2dstore-321.scope"),
            "snap-store_snap-store")
    }

    func testRejectsNonAppScopes() {
        XCTAssertNil(RunningAppScope.desktopID(fromScopeName: "session-2.scope"))
        XCTAssertNil(RunningAppScope.desktopID(fromScopeName: "user@1000.service"))
        XCTAssertNil(RunningAppScope.desktopID(fromScopeName: "app-gnome-.scope"))
    }

    // MARK: - cgroup extraction

    func testExtractsScopeFromCgroupPath() {
        let cgroup = "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-gnome-org.gnome.Nautilus-2468.scope\n"
        XCTAssertEqual(RunningAppScope.desktopID(inCgroup: cgroup), "org.gnome.Nautilus")
    }

    func testCgroupWithoutAnAppScopeIsNil() {
        XCTAssertNil(RunningAppScope.desktopID(inCgroup: "0::/user.slice/session-3.scope\n"))
    }

    // MARK: - /proc scan (temp fixture)

    func testProcScanDedupesAndSorts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("proc-\(UUID().uuidString)")
        // Realistic cgroup v2 paths: the app scope sits under the session's user@<uid>.service.
        func writeCgroup(pid: String, scope: String, user: String = "1000") throws {
            let dir = root.appendingPathComponent(pid, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "0::/user.slice/user-\(user).slice/user@\(user).service/app.slice/\(scope)\n"
                .write(to: dir.appendingPathComponent("cgroup"), atomically: true, encoding: .utf8)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        try writeCgroup(pid: "1001", scope: "app-gnome-org.gnome.Nautilus-1001.scope")
        try writeCgroup(pid: "1002", scope: "app-gnome-org.gnome.Nautilus-1002.scope")   // same app, 2nd window
        try writeCgroup(pid: "1003", scope: "app-flatpak-com.example.App-1003.scope")
        try writeCgroup(pid: "1004", scope: "session-5.scope")                            // not an app
        // Another logged-in user's app scope — world-readable, but must NOT count as ours.
        try writeCgroup(pid: "1005", scope: "app-gnome-org.example.Other-1005.scope", user: "1001")
        // A non-numeric entry (like /proc/self) must be skipped, not crash.
        let selfDir = root.appendingPathComponent("self", isDirectory: true)
        try FileManager.default.createDirectory(at: selfDir, withIntermediateDirectories: true)
        try "0::/whatever\n".write(to: selfDir.appendingPathComponent("cgroup"), atomically: true, encoding: .utf8)

        let ids = ProcRunningApps(procRoot: root, uid: 1000).runningAppIDs()
        XCTAssertEqual(ids, ["com.example.App", "org.gnome.Nautilus"],
                       "deduped, sorted, and scoped to uid 1000 (the other user's app excluded)")
    }

    func testProcScanOfMissingRootIsEmpty() {
        XCTAssertTrue(ProcRunningApps(procRoot: URL(fileURLWithPath: "/no/such/proc")).runningAppIDs().isEmpty)
    }
}
#endif
