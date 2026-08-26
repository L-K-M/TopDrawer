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
// Scope note (LP-16): this is the D-Bus / systemd / CI skeleton. It serves the
// launcher document verbatim (see `LauncherDocumentSource`) and stubs the launch
// and drop methods, so it needs neither the root `MacDring` package (whose model
// and lister types are still module-internal) nor `PictKit`. Those dependencies —
// `.package(path: "..")` and the PictKit git URL — land with LP-17, the first
// daemon features that consume their APIs, to keep this skeleton's dependency and
// build surface minimal.
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
        .package(url: "https://github.com/wendylabsinc/dbus.git", from: "0.4.1"),
    ],
    targets: [
        .target(
            name: "TopDrawerDaemon",
            dependencies: [
                // D-Bus is a Linux-only facility; on any other platform the module
                // compiles to its `#else` stubs so the package still parses there.
                .product(name: "DBUS", package: "dbus", condition: .when(platforms: [.linux])),
            ]
        ),
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
