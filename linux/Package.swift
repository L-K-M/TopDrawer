// swift-tools-version: 5.9
import PackageDescription

// The Linux daemon package (LP-16). It lives beside the root `MacDring` package
// and the `MacDring.xcodeproj`, and is built only on Linux — the macOS app never
// resolves it. Kept at swift-tools 5.9 (Swift 5 language mode), matching the root
// manifest and the Xcode project's SWIFT_VERSION = 5.0, so the whole port compiles
// under one set of language rules. It still depends on `wendylabsinc/dbus`, whose
// own manifest is tools 6.0 — a lower-tools consumer of a higher-tools package is
// allowed.
//
// Scope note: LP-16 was the D-Bus / systemd / CI skeleton and depended on neither the
// root `MacDring` package nor `PictKit`. LP-17 adds the `MacDring` path dependency —
// its `VolumeListing` / `TrashServicing` seams (LP-12) and the copied `INotifyWatcher`
// are the first MacDring APIs the daemon consumes. `PictKit` (icon store) is still not
// needed and stays deferred.
let package = Package(
    name: "topdrawerd",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "topdrawerd", targets: ["topdrawerd"]),
        // The daemon's logic lives in a library target so the tests can drive it
        // (an executable target can't be `@testable import`ed).
        .library(name: "TopDrawerDaemon", targets: ["TopDrawerDaemon"]),
    ],
    dependencies: [
        // `.upToNextMinor` rather than `from:`: dbus is pre-1.0, where a minor bump
        // conventionally carries breaking changes, so don't let a `swift package update`
        // pull 0.5+ unreviewed. (Package.resolved + --disable-automatic-resolution pins CI
        // regardless; this guards local/branch updates.)
        .package(url: "https://github.com/wendylabsinc/dbus.git", .upToNextMinor(from: "0.4.1")),
        // Declared directly because this package `import`s Logging (Daemon/TopDrawerService)
        // itself, rather than leaning on it resolving transitively through dbus.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        // The shared model/seam package that also builds the macOS app. Consumed on both
        // platforms (the daemon links it), but its volume/trash/inotify backends are all
        // #if os(Linux). Path dependency: it lives one directory up, beside this package.
        // `name:` pins the reference to "MacDring" (the manifest name) rather than the
        // checkout directory basename, which differs between CI ("TopDrawer") and other
        // build dirs — otherwise `.product(package: "MacDring")` wouldn't resolve.
        .package(name: "MacDring", path: ".."),
    ],
    targets: [
        .target(
            name: "TopDrawerDaemon",
            dependencies: [
                // D-Bus is a Linux-only facility; on any other platform the module
                // compiles to its `#else` stubs so the package still parses there.
                .product(name: "DBUS", package: "dbus", condition: .when(platforms: [.linux])),
                // Logging is used only in the Linux-guarded daemon code.
                .product(name: "Logging", package: "swift-log", condition: .when(platforms: [.linux])),
                // VolumeListing / TrashServicing seams + INotifyWatcher (LP-17).
                .product(name: "MacDring", package: "MacDring"),
                // statx(STATX_BTIME) birth-time shim for the Fresh scan (LP-18).
                .target(name: "CShims", condition: .when(platforms: [.linux])),
            ]
        ),
        // A tiny C target: one function (topdrawer_file_btime) over statx, because
        // Glibc doesn't reliably expose statx/STATX_BTIME to Swift (LP-18). Header-and-
        // one-.c; the non-Linux stub returns -1 so it still parses off Linux.
        .target(name: "CShims"),
        .executableTarget(
            name: "topdrawerd",
            dependencies: ["TopDrawerDaemon"]
        ),
        .testTarget(
            name: "TopDrawerDaemonTests",
            dependencies: ["TopDrawerDaemon"]
        ),
    ]
)
