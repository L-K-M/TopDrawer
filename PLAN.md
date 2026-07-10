# MacDring — A Modern, Fast, Simple DragThing for macOS

A clean reimagining of the classic **DragThing** utility: colored **tabs anchored to
your screen edges** that slide open into **drawers** of your apps, files, folders, and
links. Built for modern macOS, multi-monitor from day one, with tab positions that
**restore stably across restarts**.

> **Lineage.** DragThing (James Thomson / TLA Systems, 1995–2019) was a customizable
> dock that held apps, documents, folders, and URLs across multiple floating docks you
> could place anywhere — including secondary monitors. Its "drawer" mode (a dock that
> collapses to a screen-edge tab and expands when clicked) came from absorbing *Drop
> Drawers*. It was discontinued in 2019 when macOS Catalina dropped 32-bit Carbon. No
> modern replacement has filled the gap. MacDring rebuilds the one feature people miss
> most — **edge tabs → drawers** — in a small, fast, native app.

---

## 1. Goals & Non-Goals

### Goals
- **Screen-edge tabs → drawers.** Slim, colored tabs sit flush against any screen edge.
  Click (or hover) a tab and a drawer expands out from the edge showing that tab's items.
- **Holds anything launchable:** applications, files, folders, and URLs. Open with one
  click (configurable single/double click).
- **Drag-and-drop to add.** Drag a file or app from Finder onto a tab or open drawer to
  add it — the gesture the app's namesake is built on.
- **Per-tab customization, kept simple.** Each tab has its own **color**, name, and
  glyph/icon. A handful of appearance knobs (icon size, drawer layout, material), not a
  sprawling preferences panel.
- **Multiple monitors from the start.** Tabs live on a specific display + edge; the app
  reacts live to displays connecting, disconnecting, and changing resolution.
- **Stable restore after restart.** Tabs return to the same display and edge position
  even after reboot, resolution changes, or monitor reconnection — anchored by a stable
  *display identity* and a *fractional edge position*, never raw pixels.
- **Modern, native look.** Translucent materials, rounded (continuous) corners, a quick
  spring open/close, SF Symbols, light/dark adaptive — tinted by each tab's color.
- **Fast & lightweight.** A menu-bar agent with no Dock icon. Instant tab response, lazy
  drawer rendering, no heavy dependencies, **no scary permissions** for core features.

### Non-Goals (v1)
- Replacing the macOS Dock wholesale, or a running-apps "Process dock" / app switcher
  (that's [Zap](../Zap)'s job — MacDring is a *launcher*, not a switcher).
- Legacy DragThing extras: clippings store, desktop Trash, sound effects, AppleScript
  dictionary. (Clippings and per-tab hotkeys are noted as post-v1 candidates in §13.)
- iCloud sync of tab layouts (local JSON first; sync is a later candidate).
- App Store distribution in v1 (see §10 — Developer ID + notarization, like Zap).
- Skins/themes beyond per-tab color + a global material choice.

---

## 2. Design Principles

1. **Modernize the look, preserve the feel.** Old DragThing's *power* (place anything
   anywhere, color-code it, one-click launch) with a 2026 visual language — not a
   pixel-faithful retro clone.
2. **Simple by default, deep on demand.** A new user gets one starter tab and obvious
   drag-to-add. Power lives in right-click menus and a focused Settings window, not a
   wall of checkboxes.
3. **Positions are sacred.** A launcher you've arranged is muscle memory. Restoring it
   *exactly* after a restart or a monitor change is a first-class feature, not an
   afterthought — see §6.
4. **No permission friction.** Core launching needs none. Optional global hotkeys use
   Carbon (no Accessibility grant). The app should feel trustworthy and instant.
5. **Borrow Zap's house style.** Same project shape and conventions as the sibling
   [Zap](../Zap) app (see §9): agent app, `ObservableObject` preferences over
   `UserDefaults`, AppKit windowing + SwiftUI content, Xcode-16 synchronized groups.

---

## 3. High-Level Architecture

A background **menu-bar / agent app** (`LSUIElement = true`, activation policy
`.accessory`, no Dock icon). It owns a set of always-present **tab windows** anchored to
screen edges and a transient **drawer window** that expands from whichever tab is active.

```
┌──────────────────────────────────────────────────────────────────────┐
│ MacDring (LSUIElement agent app)                                       │
│                                                                        │
│  ┌─────────────────┐         ┌──────────────────────────────────────┐ │
│  │ TabStore        │  load/  │ DisplayRegistry                      │ │
│  │ (Codable JSON   │◀─save──▶│ - NSScreen ↔ CGDisplay UUID          │ │
│  │  in App Support)│         │ - didChangeScreenParameters observer │ │
│  └────────┬────────┘         └───────────────────┬──────────────────┘ │
│           │  tabs + items                        │ screens changed     │
│           ▼                                       ▼                     │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ TabController  (the brain)                                        │ │
│  │ - reconciles model + live displays → window set                  │ │
│  │ - resolves each tab's anchor → on-screen frame (EdgeLayout)      │ │
│  │ - opens/closes drawers, handles drops, launches items            │ │
│  └───────┬───────────────────────────────────────────┬──────────────┘ │
│          │ one per tab                                 │ one shared      │
│          ▼                                              ▼                │
│  ┌────────────────────┐                      ┌────────────────────────┐ │
│  │ TabWindow (NSPanel │  click / hover       │ DrawerWindow (NSPanel  │ │
│  │ borderless,        │ ───────────────────▶ │ borderless, non-       │ │
│  │ non-activating)    │                      │ activating)            │ │
│  │ SwiftUI TabStrip   │  ◀── anchored to ───  │ SwiftUI DrawerView     │ │
│  │ - color pill+glyph │                      │ - grid/list of items   │ │
│  │ - drag destination │                      │ - launch on click      │ │
│  └────────────────────┘                      └────────────────────────┘ │
│                                                                        │
│  ┌─────────────────┐   ┌────────────────────┐   ┌───────────────────┐  │
│  │ StatusItem      │──▶│ Settings (SwiftUI) │   │ ItemLauncher      │  │
│  │ (menu bar)      │   │ General/Appearance/│   │ NSWorkspace open  │  │
│  │ New Tab, Quit…  │   │ Tabs/About         │   │ app/file/url/dir  │  │
│  └─────────────────┘   └────────────────────┘   └───────────────────┘  │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │ Preferences (UserDefaults) — global appearance + behavior      │   │
│  │ CarbonHotkey (optional per-tab hotkey, no Accessibility needed) │   │
│  └────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

**Tech stack:** Swift; SwiftUI for tab/drawer/Settings content; AppKit for windowing
(`NSPanel`, `NSStatusItem`, `NSVisualEffectView`); `NSWorkspace` for launching; Carbon
`RegisterEventHotKey` for optional hotkeys; `SMAppService` for launch-at-login. Document
persisted as Codable JSON in Application Support; global prefs in `UserDefaults`.
**Targets macOS 13+.**

---

## 4. Domain Model

The whole launcher is one small, `Codable` document. Identity is by `UUID` so tabs and
items survive rename/move and reorder cleanly.

```swift
struct LauncherDocument: Codable {        // the persisted root
    var version: Int                       // schema version for migrations
    var tabs: [Tab]
}

struct Tab: Codable, Identifiable {
    let id: UUID
    var title: String
    var colorHex: String                   // per-tab color (the marquee customization)
    var glyph: TabGlyph                     // SF Symbol (visual picker) or letters/emoji
    var anchor: ScreenAnchor               // where it lives — see §6
    var items: [DrawerItem]
    var behavior: TabBehavior              // open-on-hover vs click, auto-hide, pinned
    var hotkey: HotkeySpec?                // optional, no Accessibility (Carbon)
    var gridColumns: Int                   // drawer grid width, clamped to UI range 1...12
    var gridRows: Int                      // drawer grid height, clamped to UI range 1...16
    var locked: Bool                       // if set, the tab can't be dragged to a new spot
    var kind: TabKind                      // .items | .notes | .folder | .disks | .network | .cloud | .recents | .fresh
    var notes: String                      // text for a .notes tab
    var folderBookmark: Data?; var folderURL: URL?   // linked dir for a .folder tab
    var recentsSource: RecentsSource       // .recents source: .macDring | .system | .both
    var iconStyles: [String: IconStyle]    // per-path generated-icon overrides for live items
}

// TabKind: what the drawer shows.
//   .items   — the freely-arranged grid/list of apps/files/folders/links (default)
//   .notes   — a text editor (notes persist as you type)
//   .folder  — a live, read-only listing of a chosen directory
//   .disks   — a live, read-only listing of the mounted ejectable volumes (eject)
//   .network — a live, read-only listing of mounted network shares (eject/disconnect)
//   .cloud   — a live, read-only listing of cloud-storage drives (iCloud, Dropbox, …)
//   .recents — recently opened targets (MacDring history / system Spotlight / both)
//   .fresh   — a live, read-only listing of newly-arrived files (Spotlight date-added)

struct DrawerItem: Codable, Identifiable {
    let id: UUID
    var kind: ItemKind                     // .application | .file | .folder | .url | .trash | .disk | .cloud
    var displayName: String                // overridable label
    var bookmark: Data?                    // URL bookmark (survives moves/renames)
    var url: URL?                          // for .url kind, or fallback path
    var customIconBookmark: Data?          // optional icon override (an image file)
    var iconStyle: IconStyle?              // optional generated icon (base + color + SF Symbol)
    var slot: Int                          // grid position 0...10,000; invalid values become unassigned (-1)
}

// IconStyle: a generated icon — base (.folder/.tile) + colorHex + optional SF Symbol.
// Rendered to an NSImage by IconRenderer (shared by the drawer and the editor preview).
// Persistent items carry it on the item; live items keep it on Tab.iconStyles by path.

enum ItemKind: String, Codable { case application, file, folder, url, trash, disk, cloud }
//   .trash — the desktop Trash (open it; drop files to delete; Empty Trash)
//   .disk  — a mounted volume (open in Finder; eject) — Disks / Network tabs
//   .cloud — a cloud-storage root (open in Finder) — Cloud tab

struct ScreenAnchor: Codable {             // see §6 — the stable-restore core
    var displayUUID: String                // CGDisplayCreateUUIDFromDisplayID, stable across reboots
    var edge: Edge                         // .left .right .top .bottom
    var position: Double                   // 0…1 fraction along the edge (of visibleFrame)
    var order: Int                         // edge stack order, clamped to 0...10,000
}

enum Edge: String, Codable { case left, right, top, bottom }
```

- **Files & folders** are stored as URL **bookmarks** (`URL.bookmarkData`), so an item
  keeps working if the target is moved or renamed. (Security-scoped bookmarks only become
  necessary under the App Store sandbox — see §10; the v1 non-sandboxed build resolves
  plain bookmarks without entitlements.)
- **Applications** can be stored by bookmark too, or by bundle identifier for
  resilience across app updates (`NSWorkspace.urlForApplication(withBundleIdentifier:)`).
- **A broken item** (target deleted) renders dimmed with a "relink…" affordance rather
  than vanishing — never silently lose a user's arrangement.

---

## 5. Windows: Tabs & Drawers

Tabs and drawers are **borderless, non-activating `NSPanel`s** so interacting with them
never deactivates the user's frontmost app (critical: clicking a tab to launch something
must not steal focus or churn the active-app order).

### Tab window
- `NSPanel`, `styleMask = [.borderless, .nonactivatingPanel]`,
  `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`,
  `isFloatingPanel = true`, `becomesKeyOnlyIfNeeded = true`.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` so tabs
  appear on every Space and alongside fullscreen apps.
- `level` configurable: **Floating** (always on top, default) or **Normal** (sits with
  windows). A per-tab **auto-hide / auto-fade** mode (§13) keeps tabs out of the way like
  the Dock: when idle the pill slides off its edge (leaving a sliver) or dims in place, and
  reveals when the pointer reaches that screen edge — driven by a permission-free
  `.mouseMoved` monitor.
- **Content (SwiftUI in an `NSHostingView`):** two looks, switchable globally via
  `preferences.tabStyle`:
  - **Modern** — a translucent rounded pill: the flat side kisses the screen edge,
    the two inward corners are rounded (`edgeRoundedRect`, shared with the drawer),
    an `NSVisualEffectView` blur tinted by the tab's `colorHex`.
  - **Classic** — a skeuomorphic angled "folder tab" (`ClassicTabShape`): a
    trapezoid full-width along the edge, narrowing with angled shoulders toward the
    inward side, filled with the tab's color + a raised bevel, à la DragThing. Text
    color auto-contrasts (`Color.readableForeground`).
- **Label orientation follows the edge:** horizontal on top/bottom; on **left/right
  edges the name is printed vertically** (a quarter turn) so long names fit along the
  tab's length and the tab can stay thin. The rotated label's footprint is measured
  synchronously from text metrics (not a GeometryReader round-trip) so the tab window,
  which reads `fittingSize` once at placement, sizes to the full label immediately.
- **Drag destination:** the tab accepts dropped file/app URLs (`NSDraggingDestination`)
  and adds them as items; dropping highlights the tab and, on drop, briefly opens the
  drawer so the user sees the result.
- **Reposition:** drag the tab; during the drag it snaps to and slides along the
  nearest edge as a live preview, committing the `ScreenAnchor` (edge + fraction)
  on release. Also editable in Settings → Tabs.
- **Lost-tab defense:** the panel is `isMovable = false` and observes
  `didMove`/`didResize`; any frame change it didn't initiate (e.g. a tiling tool)
  is reverted to the intended frame, so a tab can't be captured and lost.

### Drawer window
- One shared drawer `NSPanel`, which slides out **flush against the screen edge**
  (like a physical drawer) centered along the edge on the tab, while the **tab is
  pushed inward to ride on the drawer's inner face** (`EdgeLayout.openDrawerFrame` +
  `openedTabFrame`). A bottom-edge tab → drawer fills the bottom and the tab sits on
  top of it. Closing slides the tab back flush to the edge.
- **Shape:** the two corners touching the screen edge are **sharp**; only the inward
  corners are rounded (`edgeRoundedRect`, shared with the modern tab pill) — so the
  drawer reads as one piece sliding flush out of the edge.
- The drawer panel is **key but non-activating** (`KeyableDrawerPanel`,
  `canBecomeKey = true` + `.nonactivatingPanel`): it can receive keys and
  intra-window drag-and-drop (item reorder, Esc) **without activating the app**, so
  the user's frontmost app is never disturbed.
- **Open/close:** a **fade + small inward slide** over `animationMs`
  (`EdgeLayout.nudgedDrawerFrame`), with the tab sliding in sync; *Reduce Motion*
  makes it instant. The slide nudges **inward** (never off-edge) so it can't bleed
  onto an adjacent display at a shared edge.
- **Content:** SwiftUI grid (icon + label) or compact list. The grid renders one
  cell per **slot** (`DrawerMetrics.gridRowCount` rows incl. a spare row), so items
  can be **placed freely with gaps** and every cell is a drop target. Header shows
  the tab title in the tab's color. Items launch via `ItemLauncher`; every confirmed,
  Recents-eligible open updates Recents, while drawer dismissal/refresh additionally
  requires that the request still belongs to the current drawer session.
- **Spring-loaded file drops:** hovering a tab while dragging a file opens its
  drawer (after ~0.5 s). File drops onto the drawer are handled at the **AppKit
  level** — the hosting view (`DrawerHostingView`) is an `NSDraggingDestination` that
  maps the drag location through `DrawerModel.externalDropTargetFrames`, reported by
  the displayed grid, list, open group, or flattened search results. Occupied targets
  carry an item UUID plus an optional unambiguous top-level placement slot; empty cells
  retain a context-local slot for targeting, but only top-level cells carry placement
  context. Thus group children/search results resolve by identity, and group-local
  empty cells never become ambiguous top-level placements. Dropping onto an **app**
  opens with it, onto a **folder** files into it, and otherwise adds/files the drop;
  top-level placement context preserves placement near the hovered cell. SwiftUI's
  `.onDrop` is **not** used here: it fires
  unreliably in the borderless panel (especially nested in a `ScrollView`) and gives
  no hovered location — the same reason reordering uses a `DragGesture`. Folder items
  are also draggable **out** to Finder/other apps. (Dropping onto a folder **moves**
  the file, Finder-style.)
- **Auto-hide:** closes on click-outside, `Esc`, re-click of its tab, selecting an item
  (unless "keep open"/pinned), or — optionally — when the pointer leaves (hover mode).
- **Sizing:** deterministic via `DrawerMetrics` (item count + appearance), not SwiftUI
  `fittingSize`, then clamped to the target screen's `visibleFrame`.

### Multi-monitor & layout (`EdgeLayout`)
- A pure, unit-testable function: given a `ScreenAnchor`, an `NSScreen.visibleFrame`, and
  the tab's measured thickness/length, return the tab window frame (and the drawer frame
  for a given content size). No global state → easy to test (§11).
- Tabs sharing an edge on a screen keep their own `position`; a de-overlap pass folds
  `EdgeLayout.snappedAlongEdge` over them in stacking order (`order`, then `position`), so
  each tab is placed against the ones already placed. Only a tab that would overlap an
  earlier one snaps — to the **nearest legal gap** (≥ `minTabGap`) — so the
  most-recently-stacked tab (a drop, a new tab, or a move-to-edge, all bumped to the top
  `order`) is the one that yields while the tabs already there stay put. A drag previews
  this same snapped slot live and commits it on release (WYSIWYG). The settled positions
  are **persisted back**, so the stored layout is itself legal and the pass is idempotent:
  re-running it — or dragging one tab away — re-derives the same frames and nothing
  drifts. `visibleFrame` keeps tabs clear of the menu bar and the macOS Dock; if a tab's
  edge collides with the Dock's edge, nudge inward and warn in Settings.

---

## 6. Stable Multi-Monitor Restore (the marquee feature)

The hard requirement: **after a restart, monitor reconnection, or resolution change,
every tab returns to the same display and the same spot on its edge.** Absolute pixel
coordinates fail all three. The model instead stores a *stable display identity* + a
*relative position*, mirroring how DragThing anchored docks to the nearest
corner/midpoint so they survived resolution switches.

### Stable display identity
- macOS reassigns `CGDirectDisplayID`s across reboots/reconnections, and `NSScreen`
  has no durable public ID. The durable key is the display's **UUID**:
  - `NSScreen.deviceDescription[.init("NSScreenNumber")]` → `CGDirectDisplayID`.
  - `CGDisplayCreateUUIDFromDisplayID(displayID)` → `CFUUID`, **stable across reboots and
    reconnections** for the same physical display.
- `DisplayRegistry` maintains a live two-way map (UUID ⇄ current `NSScreen`) and watches
  `NSApplication.didChangeScreenParametersNotification` to rebuild it on any change.

### Relative position
- Store `edge` + `position` (a `0…1` fraction along that edge measured against
  `visibleFrame`) + `order`. On resolve, multiply the fraction by the *current*
  `visibleFrame` length → the tab stays proportionally placed when resolution changes.
- Optional snapping to canonical anchors (corner / third / midpoint) gives the tactile
  DragThing feel and makes "the tab is centered on the right edge" survive *exactly*.

### Connect / disconnect policy
On launch and on every screen-parameters change, `TabController` reconciles:
- **Display present** → resolve UUID → place/refresh the tab window on that screen.
- **Display absent** (unplugged) → **park** the tab: hide its window, keep its anchor.
  When the display returns (same UUID), the tab reappears exactly where it was. This is
  the default — positions are truly stable, nothing gets dumped onto the laptop screen.
- A General setting offers the alternative *"When a display disconnects, move its tabs to
  the main display"* for users who prefer always-visible tabs over exact restoration.
- First run / unknown UUID (e.g. importing a layout on a new machine): fall back to the
  main display, preserving edge + fraction.

This makes restore correct by construction: nothing is stored that a resolution change or
reconnection can invalidate.

---

## 7. Interaction Model

| Action | Result |
|---|---|
| Click a tab | Toggle its drawer open/closed |
| Hover a tab *(hover mode)* | Open the drawer; closes when the pointer leaves |
| Click an item | Launch app / open file / open URL / reveal or expand folder |
| Drop file(s)/app onto a tab or drawer | Add as item(s); brief drawer flash to confirm |
| Drag a tab | Re-anchor it (edge / position / screen) with snapping |
| Drag an item within/between drawers | Reorder / move it |
| Right-click a tab | New Tab, Rename, Color…, Glyph…, Move to edge/screen, Delete |
| Right-click an item | Rename, Change Icon…, Reveal in Finder, Remove |
| `Esc` / click-outside | Close the open drawer |
| Optional per-tab hotkey | Toggle that tab's drawer from anywhere (Carbon) |
| Menu-bar item | New Items/Notes/Folder/Disks/Network/Cloud/Recents Tab… (each opens a config modal), Settings…, Launch at Login, Quit |

**First-run onboarding:** create one starter tab on the right edge of the main display,
pre-populated with a couple of common apps and a hint label ("Drag apps & files here"),
so the core gesture is discoverable in seconds.

---

## 8. Customization & Settings

Global appearance/behavior live in `UserDefaults` (Zap-style `Preferences`
`ObservableObject` with validated defaults). Per-tab values live in the tab model.

**Per-tab (model):** color, name, glyph (SF Symbol or letters/emoji), edge, screen,
position, **drawer grid size (columns × rows)**, **locked**, open mode (click/hover),
auto-hide, pinned-open, optional hotkey.

> **Open-on-hover / auto-hide are global defaults a tab can override.** Both fields
> on `TabBehavior` carry an `overrides…` flag (default off): a tab follows the global
> default (`Preferences.newTabOpenOnHover` / `newTabAutoHide`, set in General →
> Drawers) until you pin a per-tab value in the Tabs pane; "Use global default"
> reverts it. `TabBehavior.resolved(openOnHoverDefault:autoHideDefault:)` does the
> fallback, read live by `TabController` at interaction time — so changing a global
> default takes effect at once without rewriting any stored tab (the old
> `updateAllBehaviors` bulk-overwrite is gone). See ANALYSIS.md I3.

**Global (`Preferences`):**

| Setting | Type | Default |
|---|---|---|
| Drawer translucency | enum (translucent/frosted/solid) | translucent |
| Drawer layout | per-tab (grid/list) | grid |
| Default tab color | Color | system accent |
| Icon size | Slider (32–128) | 64 |
| Drawer layout | Grid / List | Grid |
| Tab style | Modern / Classic | Modern |
| New-tab grid columns / rows | Steppers | 4 × 2 (per-tab override in Tabs) |
| Corner radius | Slider (0–24) | 14 |
| Tab thickness | Slider (24–64) | 36 |
| Open on | Click / Hover | Click |
| Open animation | Slider (0–300 ms) | 140 |
| Launch on | Single / double click | Single |
| Tab window level | Floating / Normal | Floating |
| Disconnect policy | Park / Move to main | Park |
| Launch at login | Toggle (`SMAppService`) | Off |

Colors persist as hex via a reused **`ColorHex`** helper (`NSColor(hex:)` / `.hexString`
+ SwiftUI `Color` bridging — lifted from Zap).

**Settings window** (SwiftUI, opened from the menu bar) tabs:
1. **General** — launch at login, open mode, animation, launch click, disconnect policy.
2. **Appearance** — **tab style (modern / classic)**, material, default color, icon size,
   layout, radius, thickness. Side (left/right) tabs print their name vertically.
3. **Tabs** — manage all tabs: list with color swatches, edge/screen pickers, per-tab
   color/glyph, and each tab's items (add/remove/reorder/relink). The home for keyboard-
   first management without dragging on screen.
4. **About** — version, lineage credit to DragThing, links.

---

## 9. Persistence

- **Document** (`tabs` + items + anchors): `Codable` → JSON at
  `~/Library/Application Support/MacDring/launcher.json`, written **atomically**
  (`.atomic`) on change (debounced). Human-inspectable and easy to back up. A `version`
  field drives forward migrations.
- **Global prefs:** `UserDefaults` (small scalar/appearance values), same pattern as
  Zap's `Preferences` — `@Published` with `didSet` persistence, range-clamped on read so
  corrupted values can't crash the UI.
- **Bookmarks** stored inside items as `Data`; resolved lazily by `BookmarkResolver`,
  which refreshes stale bookmarks (`isStale`) and marks unresolvable ones broken.
- **Crash/empty safety:** a missing/corrupt document loads as "no tabs" + offers to
  restore from the most recent `.bak` (we keep one prior copy on each successful save).

---

## 10. Permissions, Signing & Distribution

- **No special permissions for core features.** Launching apps/files/URLs uses
  `NSWorkspace`; reading dropped files uses ordinary file access (non-sandboxed build).
  This is a deliberate advantage over Zap (which needs Accessibility for its event tap).
- **Optional global hotkeys** use Carbon `RegisterEventHotKey` — **no Accessibility
  grant required** (the same no-permission path Zap uses only as a fallback).
- **`LSUIElement = true`** / `.accessory` activation policy: no Dock icon, menu-bar only.
- **Launch at login** via `SMAppService.mainApp` (macOS 13+).
- **Distribution:** Developer ID signing + notarization for direct download (hardened
  runtime). **App Store path (future):** enable the sandbox and switch file/folder items
  to **security-scoped** bookmarks (`.withSecurityScope`) with the user-selected-files
  entitlement; the model already carries bookmarks, so this is a localized change.
- **Signing note (carried from Zap):** ad-hoc debug signatures change every rebuild, which
  resets TCC-style grants. Not an issue for core MacDring (no TCC permission), but if
  hotkeys ever migrate to an event tap, sign with a stable *Apple Development* identity so
  grants persist.

---

## 11. Project Structure (proposed)

Mirrors Zap's clean module layout and **Xcode 16 file-system-synchronized groups**
(`PBXFileSystemSynchronizedRootGroup`), so new files under `MacDring/` and
`MacDringTests/` are picked up automatically — no `project.pbxproj` edits. Build settings
match Zap: `MACOSX_DEPLOYMENT_TARGET = 13.0`, `GENERATE_INFOPLIST_FILE = YES`,
`INFOPLIST_KEY_LSUIElement = YES`, `SWIFT_VERSION = 5.0`,
`PRODUCT_BUNDLE_IDENTIFIER = com.macdring.MacDring`.

```
MacDring/
├── MacDring.xcodeproj
├── MacDring/
│   ├── MacDringApp.swift          # @main enum; NSApplication, .accessory policy
│   ├── AppDelegate.swift          # status item, bootstraps controllers
│   ├── Model/
│   │   ├── LauncherDocument.swift # Codable root (+ schema version)
│   │   ├── Tab.swift
│   │   ├── DrawerItem.swift       # + fromFileURL/fromLink factory
│   │   ├── ScreenAnchor.swift
│   │   ├── Edge.swift
│   │   ├── TabGlyph.swift         # SF Symbol or monogram
│   │   ├── TabBehavior.swift      # per-tab open/hide/keep-open (+ global-default overrides)
│   │   ├── TabConcealment.swift   # pill idle auto-hide / auto-fade
│   │   ├── FolderSort.swift       # folder-tab listing order (name / date / kind)
│   │   ├── TabKind.swift          # items / notes / folder / disks / network / cloud
│   │   ├── HotkeySpec.swift       # keyCode + Carbon modifier mask
│   │   ├── IconStyle.swift        # generated icon: base + color + optional SF Symbol
│   │   ├── RecentItem.swift       # a recently-opened target (recents tab)
│   │   ├── PreferenceEnums.swift  # material/layout/disconnect/level enums
│   │   ├── ColorHex.swift         # reused from Zap
│   │   └── Preferences.swift      # UserDefaults-backed global prefs
│   ├── Store/
│   │   ├── TabStore.swift         # load/save JSON, observable, debounced atomic write
│   │   ├── BookmarkResolver.swift # bookmark ⇄ URL, staleness, broken-item handling
│   │   ├── FolderLister.swift     # live directory listing for folder tabs (sort/hidden)
│   │   ├── DisksLister.swift      # live mounted-ejectable-volume listing for disks tabs
│   │   ├── NetworkLister.swift    # live network-share listing for network tabs
│   │   ├── CloudLister.swift      # live cloud-drive listing for cloud tabs
│   │   ├── RecentsStore.swift     # recent-items history (UserDefaults JSON)
│   │   ├── RecentsLister.swift    # recent-items listing for recents tabs (source-aware)
│   │   ├── SpotlightQuery.swift   # async NSMetadataQuery (Fresh tab + system recents)
│   │   └── FreshLister.swift      # newly-arrived-file listing for fresh tabs (pure map)
│   ├── Screens/
│   │   ├── DisplayRegistry.swift  # NSScreen ⇄ CGDisplay UUID, change notifications
│   │   └── EdgeLayout.swift       # pure anchor → frame math (unit-tested)
│   ├── Tabs/
│   │   ├── TabController.swift     # reconciles model + displays → windows; the brain
│   │   ├── TabWindowController.swift
│   │   ├── TabStripView.swift      # SwiftUI tab pill: modern/classic styles, rotated side labels
│   │   └── TabStripModel.swift     # observable pill state + interaction callbacks
│   ├── Drawer/
│   │   ├── DrawerWindowController.swift
│   │   ├── DrawerModel.swift
│   │   ├── DrawerSearch.swift      # pure type-to-find filter / selection / key helpers
│   │   ├── DrawerView.swift        # SwiftUI grid/list + drag-to-reorder + search
│   │   ├── DrawerMetrics.swift     # deterministic drawer sizing (pure)
│   │   └── ItemView.swift
│   ├── Launch/
│   │   ├── ItemLauncher.swift      # NSWorkspace open app/file/url/folder + open-with
│   │   ├── FileMover.swift         # file dropped onto a folder → move it there
│   │   └── DiskEjector.swift       # unmount + eject a mounted volume (disks tab)
│   ├── Hotkeys/
│   │   ├── CarbonHotkey.swift       # optional per-tab hotkey (no Accessibility)
│   │   └── KeyCodes.swift
│   ├── Settings/
│   │   ├── SettingsWindowController.swift
│   │   ├── SettingsView.swift
│   │   ├── GeneralView.swift
│   │   ├── AppearanceView.swift
│   │   ├── TabsView.swift          # tab list + per-tab editor (TabEditor)
│   │   ├── HotkeyRecorderView.swift
│   │   ├── SymbolPickerView.swift   # searchable SF Symbol grid for tab glyphs
│   │   ├── SettingsRouter.swift     # deep-links Configure Tab → Tabs → [tab]
│   │   ├── NewTabView.swift         # New Tab modal (name/color/type/folder)
│   │   ├── NewTabWindowController.swift
│   │   ├── IconEditorView.swift      # generated-icon editor (base/color/symbol + preview)
│   │   ├── IconEditorWindowController.swift
│   │   └── AboutView.swift
│   ├── Updates/
│   │   ├── UpdateChecker.swift      # GitHub release check + update alert (reusable; mirrors Zap)
│   │   ├── GitHubReleaseClient.swift
│   │   ├── GitHubRelease.swift
│   │   ├── UpdateDownloader.swift    # downloads an asset to ~/Downloads
│   │   └── SemanticVersion.swift
│   ├── Common/
│   │   ├── VisualEffectView.swift   # NSVisualEffectView wrapper (reused from Zap)
│   │   ├── TabShapes.swift          # edgeRoundedRect + ClassicTabShape (tab/drawer shapes)
│   │   ├── ActivationPolicy.swift   # shared .regular↔.accessory revert guard (Settings/New Tab)
│   │   ├── IconRenderer.swift       # draws an IconStyle to an NSImage (drawer + editor)
│   │   └── MarkdownText.swift       # basic-Markdown renderer for the notes preview
│   └── Resources/
│       └── Assets.xcassets          # Info.plist generated
├── MacDringTests/
│   ├── EdgeLayoutTests.swift        # anchor → frame across edges/resolutions
│   ├── ScreenAnchorTests.swift      # fraction clamping + Codable
│   ├── LauncherDocumentCodableTests.swift  # encode/decode + forward-compat
│   ├── BookmarkResolverTests.swift  # bookmark round-trip, stale/broken handling
│   ├── TabStoreTests.swift          # load/save/mutations/reorder/slot-drop + .bak recovery
│   ├── TabBehaviorTests.swift       # resolved() global-default overrides + Codable
│   ├── DrawerMetricsTests.swift     # deterministic drawer sizing
│   ├── DrawerModelTests.swift       # item(atSlot:) lookup
│   ├── DrawerSearchTests.swift      # type-to-find filter / nextIndex / key classification
│   ├── DrawerItemTests.swift        # DrawerItem Codable + factories (fromFileURL/fromLink)
│   ├── FolderListerTests.swift      # directory listing (sort/hidden/slots)
│   ├── DisksListerTests.swift       # ejectable-volume filtering/sort/slots
│   ├── NetworkListerTests.swift     # network-share filtering/sort/slots
│   ├── CloudListerTests.swift       # cloud-root listing/sort/slots
│   ├── RecentsStoreTests.swift      # recents merge/dedup/cap + multi-source dedup + persistence
│   ├── RecentsListerTests.swift     # recents listing (mapping/order/slots/source)
│   ├── FreshListerTests.swift       # newly-arrived listing (order/slots/cap/scopes)
│   ├── IconStyleTests.swift         # IconStyle Codable, applyingIconStyles, IconRenderer
│   ├── MarkdownTextTests.swift      # notes-preview Markdown line classification
│   ├── TrashInspectorTests.swift    # trash entry-count / emptiness across volumes
│   ├── FileMoverTests.swift         # move-into-directory + collision rename
│   ├── SemanticVersionTests.swift   # version parse/compare (update checker)
│   ├── GitHubReleaseTests.swift     # release JSON decode + asset pick
│   ├── UpdateDownloaderTests.swift  # unique Downloads filename
│   └── PreferencesTests.swift       # defaults, clamping
├── Tools/
│   └── GenerateAppIcon.swift        # renders AppIcon.appiconset at all sizes
├── PLAN.md
├── README.md
└── AGENTS.md
```

---

## 12. Implementation Phases / Milestones

> **Status:** Phases 1–9 implemented; at the last successful build the project
> **built clean** with the **unit-test suite passing** (the pure-logic tests under
> `MacDringTests/`; exact counts drift as features land, so see CI). Several GUI test
> passes refined the behaviors below. Release signing is out of scope per the owner.
>
> **⚠️ Build-environment note (2026-06):** Xcode 26.5's build service
> (`SWBBuildService`) currently **deadlocks on the initial `clang -v -E -dM`
> compiler-info probe** on this machine — it spawns the probe but never drains its
> output pipe, so every `xcodebuild`/test run hangs at `CreateBuildDescription`. This
> is not the project: the probe runs in <0.1 s by hand, and the whole module
> **type-checks clean via `swiftc -typecheck`**. The fix is on the Xcode install
> (`sudo xcodebuild -runFirstLaunch`, then reinstall Xcode if needed). The newest GUI
> changes are therefore verified by type-check + icon render, with on-screen
> verification pending the Xcode repair.
>
> **GUI behavior (refined over two test passes):**
> - **Drawer open** — **slides** out flush against the screen edge (sized by
>   `DrawerMetrics`, animated over `animationMs`, *Reduce Motion* → instant); the
>   **tab is pushed inward to ride on the drawer's inner face** (`openDrawerFrame`
>   + `openedTabFrame`), e.g. a bottom-edge tab's drawer fills the bottom and the
>   tab sits on top of it.
> - **Tab drag** — snaps to and slides along the **nearest edge** as a live
>   preview (driven by the global mouse location, accurate across monitors),
>   committing the anchor on release.
> - **Free arrangement** — items hold an explicit grid **`slot`**, so they can be
>   placed anywhere with **gaps** (classic DragThing). Every slot — empty or not —
>   is a drop target. Drag is a `DragGesture` (the dragged item follows the cursor;
>   the slot under it is found from the cells' reported frames; `TabStore.placeItem`
>   moves it there, swapping if that slot is occupied, on release). SwiftUI's
>   `.onDrop` is **not** used for reorder — its drop callbacks don't fire inside a
>   borderless panel's grid. External file drops use the AppKit target-frame path below.
>   Because cells are keyed by slot index (reused on swap), `ItemView` reloads its
>   cached icon via `.task(id: item.id)` so the **icon follows the item** on a swap
>   (otherwise names swap but icons stay put).
> - **Lost-tab defense** — each tab panel is non-movable and **snaps back to its
>   intended frame** if an external tool (a tiling / window manager) moves or
>   resizes it, so a tab can't be dragged off to an odd place.
> - **Configure Tab…** opens Settings **directly to the Tabs pane with that tab
>   selected** (`SettingsRouter`); **Settings** content fills/resizes with its window.
> - **Per-tab drawer grid** — each tab sets its drawer's `gridColumns` × `gridRows`
>   (Tabs editor); new tabs default from General → New tab defaults.
> - **Locked tabs** — a `locked` tab ignores drag-to-reposition. The **open drawer's
>   header** shows a **lock toggle** and a **gear** (Configure Tab…); the
>   always-visible pill stays uncluttered.
> - **Glyph picker** — SF Symbols are chosen from a **searchable** visual popover
>   grid (`SymbolPickerView`); the Letters mode accepts **emoji** (with an Emoji &
>   Symbols palette button).
> - **Dragged item z-order** — the dragged drawer item is drawn in an overlay above
>   the grid (a per-cell `zIndex` is ignored inside a `LazyVGrid`).
> - App items drop the **`.app`** extension from their display name.
> - **Icons** — the **app icon** (generated by `Tools/GenerateAppIcon.swift`) is a
>   blue "screen" squircle with **three flush colored edge tabs**, the middle one
>   opened into a white drawer of app icons. The **menu-bar** glyph is a template
>   "screen" outline with **two tabs** protruding from its right edge. The **About**
>   pane shows the real app icon.
> - **Tab types** (`TabKind`) — besides the default **items** tab, a **notes** tab
>   (drawer is a text editor; edits persist via `setNotes` without reconciling the
>   open drawer; a header toggle flips to a basic-Markdown **preview** via
>   `MarkdownText`), a **folder** tab (drawer shows a directory's live contents,
>   read-only: launch + reveal, with an Open-in-Finder header button), and a
>   open drawer), a **folder** tab (drawer shows a directory's live contents,
>   read-only: launch + reveal, with an Open-in-Finder header button; per-tab sort
>   order + show-hidden, and live FSEvents refresh on directory change), and a
>   **disks** tab (drawer shows the mounted **ejectable** volumes live via
>   `DisksLister`, read-only: open in Finder + **eject** from each volume's menu;
>   it refreshes on mount/unmount via `NSWorkspace` notifications), a **network**
>   tab (drawer lists mounted **network shares** live via `NetworkLister`, read-only:
>   open in Finder + **eject**/disconnect; reuses the Disks volume notifications to
>   stay live), and a **cloud** tab (drawer lists **cloud drives** — iCloud,
>   Dropbox, … — live via `CloudLister`, read-only: open in Finder), and a
>   **recents** tab (drawer lists targets recently opened from MacDring via
>   `RecentsLister`/`RecentsStore`, read-only: re-open, or clear from the header).
>   See [docs/network-and-cloud-drives.md](docs/network-and-cloud-drives.md).
> - **New Tab modal** — the menu bar has **New Items / Notes / Folder / Disks /
>   Network / Cloud / Recents Tab…** entries; each opens a small dialog (`NewTabView`)
>   to set the name, color, type, and (for a folder) the directory, then creates it.
> - **Spring-loaded file drops** — hovering a tab while dragging opens its drawer;
>   the drawer's hosting view (`DrawerHostingView`, an **AppKit `NSDraggingDestination`**)
>   highlights the displayed target under the cursor and files there on release — onto
>   an app opens-with, onto a folder moves the file in, otherwise it adds/files the
>   drop. SwiftUI reports `DrawerModel.externalDropTargetFrames` for grids, lists, open
>   groups, and flattened search results. Occupied targets carry item identity and only
>   unambiguous top-level targets carry placement context; empty targets retain their
>   context-local slot, but group-local empty slots do not become top-level placements.
>   **Why AppKit, not
>   SwiftUI `.onDrop`:** in this borderless panel (especially nested in a `ScrollView`)
>   `.onDrop` fires unreliably and gives no hovered location — the same lesson as
>   reordering (which uses a `DragGesture`). A **folder/app** target shows a distinct
>   ring (file-into / open-with) vs. an empty slot's fill. Folder items drag **out** to
>   Finder. The open/close animation nudges **inward** + fades, so it never bleeds onto
>   an adjacent display at a shared edge.
> - **Tab styles** — a global **Modern / Classic** toggle (Appearance): modern is the
>   translucent rounded pill; classic is an angled DragThing-style **folder tab**
>   (`ClassicTabShape`) filled with the tab color + a raised bevel, auto-contrasting
>   text. Classic renders **shorter** (`Preferences.renderedTabThickness` ≈ 0.66 ×
>   `tabThickness`) and **wider** (more padding beside the name) — a squat folder tab.
> - **Vertical side labels** — tabs on the **left/right** edges print their name
>   **rotated a quarter turn** along the tab's length, so long names fit and the tab
>   can stay thin (footprint measured synchronously from text metrics).
> - **Drawer shape** — the drawer's two corners touching the screen edge are **sharp**;
>   only its inward corners are rounded, so it reads as sliding flush out of the edge.

1. **Skeleton** ✅ — Xcode project (synchronized groups, `.accessory`, `LSUIElement`),
   menu-bar `NSStatusItem`, Settings window, `Preferences` + `ColorHex`.
2. **Model & store** ✅ — `LauncherDocument`/`Tab`/`DrawerItem`/`ScreenAnchor` Codable
   (forward-compatible decoders); `TabStore` JSON load/save (atomic, debounced, `.bak`
   recovery); `BookmarkResolver`.
3. **Displays & layout** ✅ — `DisplayRegistry` (UUID mapping + change notifications) and
   pure, unit-tested `EdgeLayout` math.
4. **Tab windows** ✅ — borderless non-activating panels; colored edge pill with
   inner-rounded corners; multi-tab + multi-edge layout via `EdgeLayout`.
5. **Drawer** ✅ — expand from edge; grid/list of items; `ItemLauncher` opening
   apps/files/URLs/folders; click-outside / Esc / re-click / select dismissal; pinned
   (`autoHide` off) and `keepOpenAfterLaunch` honored.
6. **Drag-and-drop & editing** ✅ — drop-to-add on tabs/drawers; tab context menu
   (Configure / Remove) + item context menu (Open / Reveal / Remove); drag-to-reposition
   a tab (snaps to nearest edge + fractional position).
7. **Stable restore** ✅ — anchors persisted/resolved across launches; connect/disconnect
   handled via the park vs. move-to-main policy; resolution changes handled by fractions.
   *(Hardware verification is phase 10.)*
8. **Customization** ✅ — per-tab color/glyph/behavior/hotkey; global appearance settings
   (material, sizes, layout, thickness); the Tabs management pane with a per-tab editor.
9. **Optional hotkeys & login** ✅ — Carbon per-tab hotkeys with a recorder UI (no
   Accessibility); `SMAppService` launch-at-login.
10. **Polish & release** ◑ — app icon ✅ (generated by `Tools/GenerateAppIcon.swift`),
    drawer open/close slide animation ✅ (Reduce-Motion aware). Remaining: real-hardware
    GUI verification (multi-monitor, Spaces, fullscreen, drag) and Developer ID signing
    + notarization.

> Pure logic (layout math, anchor clamping/coding, Codable + forward-compat, bookmark
> staleness, store load/save, prefs) is unit-tested. Windowing, multi-monitor, Spaces,
> fullscreen, drag-to-reposition, and drag-and-drop need a real macOS GUI session and are
> verified manually (see §14).

> **One scoping note vs. the original design:** repositioning a tab is supported both by
> dragging the pill on screen *and* via the Tabs pane (edge / display / position
> controls); the optional corner/third/midpoint *snapping* during drag is reduced to
> "snap to nearest edge + free position" in v1 (full canonical-anchor snapping is a
> refinement). Drawer open/close currently orders in/out; the spring/slide animation in
> §5 is a phase-10 polish item driven by the existing `animationMs` setting.

---

## 13. Post-v1 Candidates

- **Auto-hide / reveal-on-edge-hover** tabs (Dock-style) so they never obstruct. ✅
  (per-tab **Auto-hide** slide-off / **Auto-fade** dim, revealed on edge-hover).
- **Notes tab** ✅ (a text-notes tab kind). Image/picture clippings remain a future extra.
- **Folder-as-drawer** ✅ (a `.folder` tab that mirrors a directory live).
- **Disks tab** ✅ (a `.disks` tab that lists mounted ejectable volumes; eject per volume).
- **Network tab** ✅ (a `.network` tab that lists mounted network shares — ejectable —
  via `NetworkLister`) and **Cloud tab** ✅ (a `.cloud` tab that lists cloud drives via
  `CloudLister`); see docs/network-and-cloud-drives.md.
- **Custom item icons** ✅ (per-item generated icon — folder/tile base + color + SF
  Symbol, or an image file — on any item via *Customize Icon…*; `IconStyle` +
  `IconRenderer`; see docs/custom-icons.md). Image/picture *clippings* remain a future extra.
- **Layout import/export** and optional **iCloud sync** of the document.
- **Type-to-find in an open drawer** ✅ (`DrawerSearch` + `DrawerModel`: type to filter,
  ↑/↓ select, Return launches, Esc clears/closes; input driven by `TabController`'s key
  monitor). 2-D arrow nav over the *unfiltered* slot grid is a separate follow-up.
- **Stage Manager / Mission Control** awareness and tuning.

---

## 14. Key Risks & Edge Cases

- **Focus theft** — tabs/drawers must be **non-activating** panels; launching an item
  keeps the previously-frontmost app's context. Verify clicking a tab never reorders the
  user's app focus.
- **Display disconnect/reconnect & resolution change** — the core of §6; park tabs by
  UUID and restore exactly. Test: unplug/replug, change scaled resolution, swap main
  display, laptop clamshell.
- **Fullscreen apps** cover edges — `.fullScreenAuxiliary` lets tabs show; offer
  auto-hide so they don't obstruct fullscreen video.
- **macOS Dock collision** — if a tab shares the Dock's edge, `visibleFrame` already
  excludes the Dock; nudge and warn if a chosen position would sit under it.
- **Spaces** — `.canJoinAllSpaces` + `.stationary` so tabs appear on every Space.
- **Broken / moved items** — bookmarks resolve with staleness refresh; unresolvable items
  show dimmed with relink, never silently dropped.
- **Many tabs / many items** — de-overlap layout along an edge; drawers scroll past a max
  size; lazy-render drawer content; cache file/app icons.
- **Performance** — pre-warm the shared drawer window; only the active drawer renders
  content; move/show windows without rebuilding SwiftUI hosts unnecessarily (lesson from
  Zap's overlay: reuse the model, avoid full view rebuilds on the hot path).
- **Document corruption** — atomic writes + one `.bak`; load failure degrades to empty
  with a restore offer, never a crash.
- **Borderless-panel drawing stalls** after long compositor uptime — recycle the drawer
  window when hidden if it ages out or disconnects (pattern proven in Zap).
```
