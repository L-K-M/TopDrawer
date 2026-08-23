# 05 — Top Drawer port plan: inventory, capability map, target architecture

*Findings as of 2026-08-23, from a file-by-file read of the codebase (84 app files,
11,550 LOC; 34 test files, 4,589 LOC).*

## Where the code stands today

Portability buckets (app code):

| Bucket | LOC | % | Meaning |
|---|---|---|---|
| **P1** pure logic | ~1,570 | 14% | compiles on Linux today (modulo `import CoreGraphics` → `Foundation` for CG value types in `EdgeLayout`/`DrawerMetrics`) |
| **P2** Foundation-only | ~1,771 | 15% | needs Combine→Observation migration and small checks, then compiles |
| **P3** platform service behind a seam | ~1,908 | 17% | each has a named Linux equivalent (below) |
| **P4** UI (AppKit/SwiftUI) | ~6,237 | 54% | needs the Linux frontends — includes `TabController` (1,619 LOC), whose *policies* are extractable |
| **P5** macOS-only concepts | ~64 | <1% | activation policy, NSVisualEffectView, plus corners inside P3/P4 files |

Already-portable highlights: the whole `Model/` layer (LauncherDocument, Tab,
DrawerItem¹, ScreenAnchor, DrawerGrouping, LenientDecoding…), `EdgeLayout` (331 LOC of
pure y-up geometry — the crown jewel, fully unit-tested), `DrawerMetrics`,
`DrawerSearch`, `FreshLister`/`RecentsLister`, `SemanticVersion` + the GitHub release
client, `TimeBucket`. The listers (`DisksLister`, `NetworkLister`, `CloudLister`,
`FolderLister`) already separate a pure `Volume`/item model from the FileManager
bridge; `ItemLauncher` is already fully seamed with injectable closures.

¹ `DrawerItem` uses CryptoKit `SHA256` for stable transient IDs — swift-crypto
(`import Crypto`) is API-compatible on Linux.

## Capability map: every macOS dependency → its Linux equivalent

| Capability (macOS API) | Linux equivalent | Fit |
|---|---|---|
| Edge tab windows (`NSPanel` non-activating, `.canJoinAllSpaces`, orderFrontRegardless) | **gtk4-layer-shell** surfaces (KDE/wlroots) / extension-positioned GTK windows (GNOME) — see [02](02-desktop-constraints.md) | layer-shell tier is a *better* fit: anchoring is declarative, no frame defense, `keyboard_interactivity=on_demand` ≈ non-activating |
| Display identity (`CGDisplayCreateUUIDFromDisplayID`) | (manufacturer, model, description) tuple from `GdkMonitor` / Mutter EDID via extension; `items-changed` for hotplug | good; connector names are hints, not identity |
| Global mouse monitors for reveal/dismiss (`NSEvent.addGlobalMonitor…`) | layer-shell overlay sliver strips (hover) / `Meta.Barrier` via extension; outside-click dismissal via grab-on-open or compositor `closed` events | different mechanism, same UX |
| Carbon hotkeys (`RegisterEventHotKey`) | GlobalShortcuts portal (GNOME 48+/KDE) / extension keybindings / GSettings media-keys fallback | good on 25.10+; persisted `HotkeySpec` (Carbon keycodes) needs re-record on Linux |
| Spotlight recents (`NSMetadataQuery` + `kMDItemLastUsedDate`) | **`recently-used.xbel`** (GTK recent files; written by GTK apps, Firefox, LibreOffice, Electron apps) — plain XML, parse + inotify-watch it; optionally TinySPARQL/LocalSearch | decent; narrower coverage than Spotlight (Qt/CLI apps don't write it) |
| Spotlight fresh files (`kMDItemDateAdded`) | **LocalSearch (Tracker) SPARQL** over D-Bus — `nfo:fileCreated` (btime via statx) is indexed; caveat: default scope is XDG dirs and **Downloads is indexed non-recursively**; plus our own **inotify** scanner (`FreshScanner`'s `dateAdded` closure is already injectable → birth-time/mtime) | good with both sources combined; no TCC prompts to dodge on Linux — direct scanning is free |
| Folder/Trash watches (`DispatchSource` + `O_EVTONLY` — kqueue) | **inotify** (~300-line wrapper; `IN_CREATE\|IN_MOVED_TO\|IN_DELETE` on the directory) | direct replacement; `DispatchSource.makeFileSystemObjectSource` does not exist on Linux |
| Volumes (`FileManager.mountedVolumeURLs` + volume keys) | **GIO `GVolumeMonitor`** (mounts/volumes/drives + signals, eject) or UDisks2 D-Bus; network = `filesystem::remote` / fstype in {cifs, nfs, sshfs, davfs}; GVfs mounts appear under `$XDG_RUNTIME_DIR/gvfs` | high fidelity, including eject spinners (async eject with callback) |
| Cloud tab (`~/Library/CloudStorage`, iCloud) | GVfs/GOA mounts (`google-drive://`, `onedrive://` since GNOME 46) + probes: `~/.dropbox/info.json` (documented by Dropbox), `fuse.rclone` fstype, `~/OneDrive` | concept ports; providers differ (no iCloud); gvfs google-drive exposes doc-IDs not filenames — open via URI, not path |
| Trash (getattrlist hack, `NSAppleScript` empty-trash) | **freedesktop Trash spec**: `gio trash` / `g_file_trash()`; count via `trash:///` attribute `trash::item-count` (what Nautilus uses); empty via `gio trash --empty`; open via `xdg-open trash:///`. Note: `FileManager.trashItem(at:)` **does not exist on Linux** (compile error — guard `FileMover`'s default argument with `#if os(macOS)`), and `.trashDirectory` maps to `~/.Trash`, not the spec location | *simpler* than macOS — the entire getattrlist/AppleScript machinery exists only to dodge TCC, which has no Linux analogue |
| Launching (`NSWorkspace.openApplication`, open-with) | **GAppInfo/GDesktopAppInfo**: `launch_default_for_uri`, `g_desktop_app_info_new("app.desktop").launch(files:)` (open-with), `xdg-mime` default queries; reveal-in-file-manager via `org.freedesktop.FileManager1.ShowItems` D-Bus | full parity; app items become desktop-file IDs |
| Running-app dot (`NSWorkspace.runningApplications` + notifications) | per-tier: extension (`Shell.WindowTracker`) / plasma-window-management / wlr-foreign-toplevel / heuristics on stock GNOME | good except stock-GNOME tier |
| Login item (`SMAppService`) | XDG autostart `.desktop` in `~/.config/autostart/` (or systemd user service for the daemon) | direct |
| Menu-bar item (`NSStatusItem`) | **StatusNotifierItem over D-Bus**; Ubuntu ships the AppIndicator extension enabled by default | good on Ubuntu; hand-rolled (no GTK4 API) |
| Foreign-fullscreen detection (`CGWindowListCopyWindowInfo`) | **delete it** — the macOS Spaces pathology it works around doesn't exist; layer-shell handles over-fullscreen declaratively | subsystem disappears |
| Favicons (URLSession + ImageIO ICO decode) | URLSession (FoundationNetworking) + gdk-pixbuf — plus a ~100-line ICO container splitter (gdk-pixbuf's ICO loader can't read PNG-compressed entries, which modern favicons use) | cache/dedup/eviction logic ports as-is |
| SF Symbols (`TabGlyph`/`IconStyle` values, `SymbolPickerView`, `IconRenderer`) | mapped icon set (see [04](04-ui-frameworks.md)): SF names **cannot ship on Linux** (license); curate a mapping for the ~300 symbols in `SymbolPickerView`'s list; render via Cairo + librsvg | mechanical but real work; do the `IconName` abstraction on macOS first |
| Visual effects (`NSVisualEffectView`) | translucent solid color (compositor blur is niche/KDE-only) | acceptable cosmetic loss |
| Security-scoped-ish bookmarks (`URL.bookmarkData` alias records) | store absolute paths (+ optional dev/inode pair for rename tracking). Every read path already falls back to `item.url`, so Linux can ignore bookmark blobs in existing documents | graceful |
| Update flow (GitHub releases, .dmg/.zip preference) | same client code; prefer `.AppImage`/`.deb`/`.tar.gz` assets; or apt handles updates entirely on the deb channel | shallow |
| `UserDefaults` prefs, JSON document store | work as-is; land under `~/.config` (plists) and `~/.local/share/MacDring/` (XDG mapping is implemented in swift-foundation) | direct |

## Document compatibility

The JSON schema is mostly neutral; the non-neutral fields degrade gracefully by
existing design:

- `anchor.displayUUID` — CG UUID string; unknown UUIDs already fall back to the main
  display, so imported Mac layouts land sanely.
- `bookmark`/`customIconBookmark`/`folderBookmark` — opaque Darwin blobs; every
  consumer falls back to the sibling absolute-path field. Linux ignores them.
- `TabGlyph.symbol`/`IconStyle.symbol` — SF Symbol names → mapping table.
- `hotkey` — Carbon keycodes → re-record on Linux.
- Absolute mac paths in items obviously don't resolve; import keeps the tabs, items
  show as missing. Everything else (colors, edges, fractions, slots, notes, layout
  enums) is genuinely portable.

**The lenient-decode architecture is an invariant, not a convenience** — the
Failable-wrapper + quarantine + version-gate behavior in `TabStore` must be preserved
exactly on Linux, or a debounced autosave can permanently destroy user documents.

## Target architecture

```
                    ┌──────────────────────────────┐
                    │   TopDrawerCore (SwiftPM)     │  shared with macOS
                    │  model · stores · listers'    │
                    │  logic · EdgeLayout · search  │
                    │  grouping · recents · updates │
                    └──────┬────────────────┬───────┘
        macOS app          │                │        topdrawerd (Linux daemon)
   AppKit/SwiftUI as today │                │  volumes·trash·launch·watch·hotkeys
                           │                │  persistence · D-Bus interface
                           │                ├──────────────┬─────────────────┐
                           │                │              │                 │
                           │        layer-shell frontend   │        GNOME Shell extension
                           │        (GTK4 + cairo tabs,    │        (GJS: positions the app's
                           │         KDE/wlroots/COSMIC)   │         windows, barriers, keybinds,
                           │                               │         running-apps feed over D-Bus)
```

- **Step 1 (benefits macOS too):** extract the policies currently inlined in
  `TabController` — reconcile/park rules, de-overlap fold (persist-back with
  `notify:false`), drag magnetization + `topOrder` restacking, spring-load/peek state
  machine, hotkey-conflict handoff, Spotlight-watch keying — into plain types in the
  core package with the existing tests carried over. `TabController` becomes a thin
  AppKit adapter; the Linux frontends consume the same policies.
- **Step 2:** stand up `topdrawerd` with the P3 seams implemented for Linux
  (GVolumeMonitor, inotify, GAppInfo, XDG trash, xbel+LocalSearch recents, SNI tray,
  portal hotkeys) and a D-Bus schema (tabs/items/state; introspection-XML-first so
  both frontends and the GJS side can codegen).
- **Step 3:** layer-shell frontend first (it is the simpler one and proves the whole
  stack on Kubuntu/Sway), then the GNOME extension.

## Tests

~80–85% of test LOC runs on Linux after the P1/P2 ports: all the pure suites
(EdgeLayout 45 tests, TabStore 67, listers, grouping, search, metrics, semver,
lenient decoding, FreshScanner with injected `dateAdded`, FileMover with injected
trash, ItemLauncher with injected seams…). Add a Linux CI job early — it is the
cheapest possible regression net for the core extraction. Not portable:
BookmarkResolver (becomes the conformance test of the path-based seam), ColorHex
(NSColor), KeyCodes (Carbon), TrashInspector (rewrite scenarios against XDG trash),
IconRenderer half of IconStyle.

## Surprises a porting engineer must not miss

(Condensed from the full inventory; each was verified in source.)

1. **Coordinate system:** all of `EdgeLayout` is bottom-left-origin y-up;
   `DrawerHostingView` flips manually for SwiftUI; vertical-edge fractions are
   computed as `(maxY − y)/height`. Do exactly one deliberate flip at the Linux
   boundary and keep the y-up tests as the source of truth.
2. **`TrashInspector` looks like kernel code** (raw `getattrlist`, hand-packed
   buffers) and `FileMover.emptyTrash` drives Finder via AppleScript — both exist
   *only* to dodge macOS TCC prompts. On Linux, delete both; list/empty the XDG
   trash directly.
3. **The no-Accessibility permission model shaped everything** (Carbon over event
   taps, mouse-only global monitors, Spotlight over scans). On Linux those
   constraints evaporate — but so does free global-mouse monitoring (Wayland);
   the replacement is architectural (barriers/slivers), not API-for-API.
4. **Drag-pasteboard sniffing** for concealed-tab peek has no Linux equivalent at
   all; redesign around drag-enter on the sliver.
5. **Non-activating-panel semantics are load-bearing** (clicks must not steal
   focus): layer-shell `keyboard_interactivity` covers it; on GNOME the extension
   must manage focus explicitly.
6. **`NSScreen.main` is deliberately avoided** (`DisplayRegistry.primaryScreen` uses
   `screens.first` because `.main` follows key focus — which can be our own panel).
   Preserve the equivalent choice in GDK terms.
7. **Undocumented API touches to replace:** `NSImage(named: "NSTrashEmpty"/"NSTrashFull")`,
   `NSAnimationEffect.poof`, stringly-typed `NSScreenNumber`.
8. **Window sizing reads `fittingSize` synchronously** (rotated label metrics via
   `NSString.size`); the GTK frontends need equivalent synchronous text measurement
   (Pango does this fine).
9. **External drops are architecture, not widget:** the view reports target frames
   (PreferenceKeys), native DnD resolves them (`ExternalDropTarget.target(at:)` is
   pure geometry). Replicate the architecture with `GtkDropTarget` + reported
   frames; don't look for an `.onDrop` equivalent.
10. **PictKit rungs 3–4 of the icon ladder** (shared store, un-jailed bundle artwork)
    can be dropped initially without breaking rungs 1/2/5 — but the store itself
    ports (see [06](06-pict-port.md)), and on Linux rung 4's analogue is icon-theme
    lookup.
11. **Update checker, `.bak` rotation, corrupt-quarantine, newer-version-refusal**:
    keep the exact semantics; they are tested and load-bearing.
12. **Test-host guards** (`NSClassFromString("XCTestCase")`) — keep an equivalent in
    the Linux test runner so tests never touch the developer's real
    `~/.local/share/MacDring/launcher.json`.
