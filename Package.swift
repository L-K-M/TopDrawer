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
    // LP-11: pure spring-load/drag-peek state machine + hotkey-conflict resolution,
    // lifted out of TabController.
    "Screens/SpringLoadPolicy.swift",
    "Hotkeys/HotkeyRegistrationPolicy.swift",
    // LP-12: platform seams for volumes / trash / launching. The listers' pure cores
    // compile as-is; their FileManager volume bridge, NSWorkspace, NSAppleScript, and
    // FileManager.trashItem are macOS-only and guarded. TrashInspector stays macOS-only
    // (Darwin getattrlist) — only its shape is formalized as TrashServicing.
    // LP-13: the platform-neutral icon-name layer (SF name → Linux Lucide name) + the
    // curated symbol list and its mapping data. IconRenderer/SymbolPickerView stay
    // macOS-only; only rendering resolves through IconName.
    "Model/IconName.swift",
    "Model/IconMap.swift",
    "Model/CuratedSymbols.swift",
    // LP-13 part 2: platform seams for login item + display identity. The macOS
    // conformances (SystemLoginItem's SMAppService branch, DisplayRegistry) stay
    // macOS-only; the protocols and the Linux no-op login item compile here.
    "Model/LoginItemManaging.swift",
    "Screens/DisplayIdentity.swift",
    // LP-17: the generic inotify directory watcher (Linux-only; a whole-file
    // #if os(Linux) guard, so Xcode's synchronized MacDring/ group compiles it to
    // nothing on macOS). Feeds the daemon's Trash / folder-tab watches. See the CInotify
    // systemLibrary target below.
    "Common/INotifyWatcher.swift",
    // LP-13 part 3: the global-hotkey seam. The protocol + opaque HotkeyToken compile
    // here; the macOS CarbonHotkeyRegistrar (and CarbonHotkey it wraps) stay macOS-only
    // behind #if canImport(Carbon), so Linux registers no hotkey until its backend lands.
    "Hotkeys/GlobalHotkeyRegistering.swift",
    "Store/VolumeListing.swift",
    "Store/DisksLister.swift",
    "Store/NetworkLister.swift",
    "Store/CloudLister.swift",
    "Launch/AppLaunching.swift",
    "Launch/ItemLauncher.swift",
    "Launch/FileMover.swift",
    "Launch/TrashServicing.swift",
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
    // LP-11
    "SpringLoadPolicyTests.swift",
    "HotkeyRegistrationPolicyTests.swift",
    // LP-13: the icon-name layer + mapping-completeness test.
    "IconNameTests.swift",
    // LP-12: the volume listers + launch/move seams now reach Linux.
    "VolumeListingTestSupport.swift",
    "DisksListerTests.swift",
    "NetworkListerTests.swift",
    "CloudListerTests.swift",
    "ItemLauncherTests.swift",
    "FileMoverTests.swift",
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
                // The inotify(7) syscalls for INotifyWatcher (LP-17). Linux-only, so the
                // macOS build never sees it — and MacDring.xcodeproj never resolves this
                // manifest anyway.
                .target(name: "MacDringCInotify", condition: .when(platforms: [.linux])),
            ],
            path: "MacDring",
            // macOS-bundle artifacts that have no place in a Linux library build.
            exclude: ["Resources", "MacDring.entitlements"],
            sources: macDringSources
        ),
        // A header-only system-library shim exposing the inotify(7) syscalls (LP-17),
        // mirroring PictKit's CInotify. The IN_* masks are hard-coded in INotifyWatcher,
        // not imported from here (see CInotify/shim.h). Named MacDringCInotify (not the
        // dir's `CInotify`) so it can't collide with PictKit's identically-named module
        // once both packages land in the daemon's graph.
        .systemLibrary(name: "MacDringCInotify", path: "CInotify"),
        .testTarget(
            name: "MacDringTests",
            dependencies: ["MacDring"],
            path: "MacDringTests",
            sources: macDringTestsSources
        ),
    ]
)
