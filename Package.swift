// swift-tools-version: 5.9
import PackageDescription

// This root manifest exists for the Linux port only. macOS builds through
// `MacDring.xcodeproj` (`xcodebuild -project …`) and never touches this package,
// so the curated `sources:` lists below are what compile on Linux and are inert on
// macOS. The library target is named `MacDring` on purpose: the test files' bare
// `@testable import MacDring` then compiles unmodified on Linux. As the port lands
// (LP-07 onward) more files join these lists until the whole module builds here;
// SwiftPM warns that the not-yet-listed files are "unhandled", which is expected
// and shrinks over time. Those warnings do NOT fail the build, so a new pure-core
// file or test added on the macOS side must also be added to the list below, or
// Linux CI silently skips it. See docs/linux-port/implementation-plan.md §LP-02.
//
// swift-tools-version 5.9 keeps these files in Swift 5 language mode, which matches
// the Xcode project's SWIFT_VERSION = 5.0 — so both platforms compile the pure core
// under the same language rules and the Linux CI is a faithful signal, neither
// stricter nor looser than the Xcode build. Move both together if the project ever
// adopts Swift 6 mode.

// The pure-core files that compile on Linux today (all `Model/` except ColorHex
// and Preferences — both AppKit/SwiftUI — plus the layout/search/update math).
let macDringSources: [String] = [
    "Model/DrawerGrouping.swift",
    "Model/DrawerItem.swift",
    "Model/Edge.swift",
    "Model/FolderSort.swift",
    "Model/HotkeySpec.swift",
    "Model/IconStyle.swift",
    "Model/LauncherDocument.swift",
    "Model/LenientDecoding.swift",
    "Model/PersistedLayoutBounds.swift",
    "Model/PreferenceEnums.swift",
    "Model/RecentItem.swift",
    "Model/RecentsSource.swift",
    "Model/ScreenAnchor.swift",
    "Model/Tab.swift",
    "Model/TabBehavior.swift",
    "Model/TabConcealment.swift",
    "Model/TabGlyph.swift",
    "Model/TabKind.swift",
    "Screens/EdgeLayout.swift",
    "Drawer/DrawerMetrics.swift",
    "Drawer/DrawerSearch.swift",
    "Drawer/ExternalDropTarget.swift",
    "Tabs/DrawerLaunchRequest.swift",
    "Common/TimeBucket.swift",
    "Updates/SemanticVersion.swift",
    "Updates/GitHubRelease.swift",
    "Store/BookmarkResolver.swift",
    // LP-07: the observable stores/models + prefs. `ObservationCompat` is the Combine
    // stand-in they need on Linux (macOS uses real Combine and skips that file).
    "Common/ObservationCompat.swift",
    "Store/TabStore.swift",
    "Store/RecentsStore.swift",
    "Store/FolderLister.swift",
    "Model/Preferences.swift",
    "Drawer/DrawerModel.swift",
    "Tabs/TabStripModel.swift",
    // LP-08: the recents/fresh listers + their platform-neutral query vocabulary
    // (RecentFileHit/RecentQueryMode/RecentFilesQuerying). SpotlightQuery itself stays
    // macOS-only (NSMetadataQuery) behind its own #if os(macOS) and is not listed here.
    "Store/RecentFilesQuery.swift",
    "Store/RecentsLister.swift",
    "Store/FreshLister.swift",
    "Store/FreshScanner.swift",
    // LP-09: pure tab-placement decisions (reconcile park/move-to-main + de-overlap fold)
    // lifted out of the macOS-only TabController.
    "Screens/TabPlacementPolicy.swift",
    // LP-10: pure drag-snap/magnetization + z-restack decisions, also lifted out of
    // TabController.
    "Screens/TabDragPolicy.swift",
]

let macDringTestsSources: [String] = [
    "EdgeLayoutTests.swift",
    "ScreenAnchorTests.swift",
    "LauncherDocumentCodableTests.swift",
    "LenientDecodingTests.swift",
    "TabBehaviorTests.swift",
    "DrawerItemTests.swift",
    "DrawerGroupingTests.swift",
    "DrawerMetricsTests.swift",
    "DrawerSearchTests.swift",
    "DrawerLaunchRequestTests.swift",
    "ExternalDropTargetTests.swift",
    "TimeBucketTests.swift",
    "SemanticVersionTests.swift",
    "GitHubReleaseTests.swift",
    "TabStoreTests.swift",
    "RecentsStoreTests.swift",
    "FolderListerTests.swift",
    "PreferencesTests.swift",
    "DrawerModelTests.swift",
    // Linux-only: pins the ObservationCompat shim (compiles to nothing on macOS).
    "ObservationCompatTests.swift",
    // LP-08: recents/fresh listers now reach Linux (RecentsLister decoupled from
    // SpotlightQuery via RecentFilesQuery's neutral types).
    "RecentsListerTests.swift",
    "FreshListerTests.swift",
    "FreshScannerTests.swift",
    // LP-09
    "TabPlacementPolicyTests.swift",
    // LP-10
    "TabDragPolicyTests.swift",
]

let package = Package(
    name: "MacDring",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacDring", targets: ["MacDring"])
    ],
    dependencies: [
        // Stands in for CryptoKit on Linux only (identical SHA256 API). Adding it
        // Linux-only keeps the Xcode build — which never resolves this manifest —
        // free of the dependency.
        .package(url: "https://github.com/apple/swift-crypto.git", "4.0.0" ..< "5.0.0"),
    ],
    targets: [
        .target(
            name: "MacDring",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.linux])),
            ],
            path: "MacDring",
            // macOS-bundle artifacts that have no place in a Linux library build.
            exclude: ["Resources", "MacDring.entitlements"],
            sources: macDringSources
        ),
        .testTarget(
            name: "MacDringTests",
            dependencies: ["MacDring"],
            path: "MacDringTests",
            sources: macDringTestsSources
        ),
    ]
)
