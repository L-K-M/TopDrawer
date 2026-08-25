# AGENTS.md

Guidance for AI coding agents working in the **Top Drawer** repository.

## What Top Drawer Is

Top Drawer is a fast, modern reimagining of the classic **DragThing**: colored
**tabs anchored to screen edges** that expand into **drawers** of apps, files,
folders, and URLs. It is multi-monitor aware and restores tab positions stably
across restarts. See `PLAN.md` for the full design, and `README.md` for the user
view.

## Tech Stack

- **Language:** Swift (Swift 5 language mode — `SWIFT_VERSION = 5.0`).
- **UI:** SwiftUI for the tab pill, drawer, and Settings content; AppKit for
  windowing (`NSPanel`, `NSStatusItem`, `NSVisualEffectView`).
- **System APIs:** `NSWorkspace` (launching), `CGDisplayCreateUUIDFromDisplayID`
  (stable display identity), Carbon `RegisterEventHotKey` (optional per-tab
  hotkeys — no Accessibility needed), `SMAppService` (launch at login).
- **Persistence:** a Codable `LauncherDocument` as JSON in
  `~/Library/Application Support/MacDring/launcher.json`; app-wide settings in
  `UserDefaults`.
- **Min target:** macOS 13 (Ventura). **Built with Xcode 16+** (uses
  `UnevenRoundedRectangle`, `SMAppService`, file-system-synchronized groups).
- **App type:** menu-bar agent (`LSUIElement = true`, `.accessory` policy, no
  Dock icon).

## Build & Run

The Xcode project uses **file-system-synchronized groups**, so new files added
under `MacDring/` or `MacDringTests/` are picked up automatically — no
`project.pbxproj` edits needed.

```bash
# Build
xcodebuild -project MacDring.xcodeproj -scheme MacDring -configuration Debug build

# Run unit tests (pure logic: layout, anchors, Codable, bookmarks, store, prefs)
xcodebuild -project MacDring.xcodeproj -scheme MacDring -destination 'platform=macOS' test
```

Prefer building/running from Xcode during development so window behavior and the
menu-bar item appear in a real GUI session.

The app icon is derived from the master artwork `Tools/AppIcon-source.png`
(an open wooden drawer of glowing app tiles). `Tools/README.md` documents how
the `AppIcon.appiconset` slots are regenerated from it.

## Module Layout

Mirrors `PLAN.md §11`. Keep modules aligned:

- `Model/` — Codable model (`Tab`, `DrawerItem`, `ScreenAnchor`, `Edge`,
  `TabGlyph`, `TabBehavior`, `HotkeySpec`, `IconStyle`, `LauncherDocument`),
  `ColorHex`, `Preferences`, and the small UI enums in `PreferenceEnums.swift`.
- `Store/` — `TabStore` (JSON load/save), `RecentsStore` (recent-items history),
  `BookmarkResolver`, and the live transient listers (`FolderLister`, `DisksLister`,
  `NetworkLister`, `CloudLister`, `RecentsLister`, `FreshLister`). `SpotlightQuery`
  wraps `NSMetadataQuery` — the one **async** lister, backing the Fresh tab and the
  system source of Recents (reads the Spotlight index only; no special permission).
- `Screens/` — `DisplayRegistry` (UUID mapping) and the pure `EdgeLayout` math.
- `Tabs/` — `TabController` (the orchestrator), `TabWindowController`,
  `TabStripView` (modern pill / classic folder tab; vertical side labels),
  `TabStripModel`.
- `Drawer/` — `DrawerWindowController` (incl. `DrawerHostingView`, the AppKit
  `NSDraggingDestination` that handles spring-loaded per-slot file drops),
  `DrawerView`, `DrawerModel`, `ItemView`, and `DrawerSearch` (pure type-to-find
  filter / selection / key-classification helpers).
- `Launch/` — `ItemLauncher`. `Hotkeys/` — `CarbonHotkey`, `KeyCodes`.
- `Settings/` — the SwiftUI settings window and panes, plus the small modal
  windows (`NewTabView`/Controller, `IconEditorView`/Controller).
- `Common/` — `VisualEffectView`; `TabShapes` (`edgeRoundedRect` for the
  inward-rounded/edge-sharp tab pill + drawer, and `ClassicTabShape`);
  `ActivationPolicy` (the shared `.regular`↔`.accessory` revert guard);
  `IconRenderer` (draws an `IconStyle` to an `NSImage`); `MarkdownText` (the notes
  preview's basic-Markdown renderer).

## Conventions

- Follow the Swift API Design Guidelines.
- One type per file; file name matches the primary type. (Small exceptions:
  `PreferenceEnums.swift` groups four related UI enums; `DrawerItem.swift`
  carries its `fromFileURL`/`fromLink` factory extension.)
- Use `// MARK:` to organize sections.
- Avoid force-unwraps outside tests.
- Keep `EdgeLayout` **pure** (no global state, no AppKit beyond `CGGeometry`) so
  it stays unit-testable — it's the geometry backbone.

## Dependencies

Exactly one: [`PictKit`](https://github.com/L-K-M/Pict), a first-party SwiftPM
package holding the shared icon store and resolution ladder that Zap, Jetty and
the Pict editor also use. Top Drawer **reads** it and writes nothing — editing
lives in Pict, which needs no permissions and can be sandboxed.

Icon precedence in `ItemView.resolveIcon`, top rung first:

1. the item's `customIconBookmark` (an image file) — unchanged
2. the item's `iconStyle` (a generated folder/tile) — unchanged
3. the shared store — an icon set in Pict, Zap or Jetty
4. the target's own un-masked bundle artwork
5. the kind-specific default (drive, cloud, favicon, Trash, `NSWorkspace`)

Rungs 1 and 2 staying on top is what makes this invisible on upgrade, and it is
also a feature: two items pointing at one app are allowed to differ.

## Critical Constraints

- **No scary permissions for core features.** Launching uses `NSWorkspace`.
  Per-tab hotkeys use Carbon `RegisterEventHotKey` (no Accessibility). The
  click-outside dismiss uses a global **mouse** monitor (allowed without
  permission) and a **local** key monitor for Esc. **Never** add a *global key*
  monitor or a `CGEventTap` — that would require Accessibility/Input Monitoring
  and break the "no-permission" promise.
- **Tabs and drawers must stay non-activating** (`NSPanel` with
  `.nonactivatingPanel`). Clicking a tab or launching an item must never steal
  focus from the user's frontmost app.
- **Stable restore is sacred.** Persist a tab's location as a display **UUID** +
  **edge** + **fractional position** — never raw pixel coordinates. All on-screen
  placement goes through `EdgeLayout` against `NSScreen.visibleFrame`.
- **Show on every Space / over fullscreen:** keep `collectionBehavior` =
  `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` on tab/drawer panels.
- **Keep `LSUIElement = true`** (no Dock icon); Settings temporarily switches to
  `.regular` and back to `.accessory` on close.

## Testing Notes

- Unit-test pure logic: `EdgeLayout` geometry, `ScreenAnchor` clamping/coding,
  `LauncherDocument`/`DrawerItem` Codable + forward-compat, `BookmarkResolver`,
  `TabStore` load/save/mutations, `Preferences` defaults/clamping.
- `AppDelegate.applicationDidFinishLaunching` is guarded by `isRunningTests`, so
  the test host doesn't spin up windows.
- Window placement, multi-monitor, Spaces, fullscreen, drag-to-reposition, and
  drag-and-drop need a **real GUI session** and are verified manually.
- **When `xcodebuild` hangs** at the `clang -v -E -dM` probe (a known Xcode 26.5
  `SWBBuildService` deadlock — see `PLAN.md §12`), you can still: **type-check** the
  whole module with `xcrun --sdk macosx swiftc -typecheck -target arm64-apple-macos13.0
  $(find Top Drawer -name '*.swift')`, and **regenerate the app icon** with `swift
  Tools/GenerateAppIcon.swift` — both invoke the compiler directly and don't touch the
  wedged build service. Fix the build service with `sudo xcodebuild -runFirstLaunch`.

## AI review scope

GLM review defaults to **hybrid**: the first review is full, then follow-ups
review changes since the last completed review plus a rotating sample of older
PR changes. Keep hybrid for normal implementation/fix cycles.

Before the next review-triggering push, apply at most one override label:

- `zai-review:full` for high-risk changes, force-push recovery, or a deliberate
  final deep audit.
- `zai-review:hybrid` to explicitly select the normal delta-plus-audit mode.
- `zai-review:incremental` only for low-risk, latency-sensitive follow-ups
  after a completed full review; this omits the rotating old-code audit.

Labels select the next run but do not trigger one themselves. Remove an override
to return to hybrid. Missing/incomplete state and non-ancestor history safely
fall back to a full review.

## Do / Don't

- **Do** update `PLAN.md` when the design changes, and keep `README.md` in sync.
- **Do** keep file/folder items working via bookmarks; render broken items
  dimmed rather than dropping them.
- **Do** assume Developer ID + notarization (not the App Store) for v1; the
  sandbox/security-scoped-bookmark path is a documented future change.
- **Don't** add heavy dependencies; prefer system frameworks.
- **Don't** persist absolute window frames, or let a tab/drawer activate the app.
- **Don't** rely on SwiftUI `.onDrop` for drops *into the drawer* — its callbacks
  fire unreliably in the borderless panel (more so nested in a `ScrollView`) and give
  no hovered location. For **internal reorder** use a `DragGesture` + reported cell
  frames; for **external file drops** use the AppKit `NSDraggingDestination` on the
  drawer's hosting view (`DrawerHostingView`), mapping the converted drag location to
  a slot via `DrawerModel.slotFrames`. (The tab *pill* still uses `.onDrop` — that one
  works, and it's only used to add-to-tab / trigger the spring-open hover.)
