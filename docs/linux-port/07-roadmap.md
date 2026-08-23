# 07 — Roadmap, packaging, risks

*As of 2026-08-23. Effort figures are rough relative sizes, not commitments.*

## Guiding principle

Do the *cheap, reversible, macOS-improving* work first; make the one genuinely novel
bet (the GNOME extension) last, after the daemon and the layer-shell frontend have
proven the shared core. Every phase leaves the Mac apps strictly better factored.

## Phases

### Phase 0 — CI + PictKit seams (small)

- Add Linux CI jobs to both repos (`swift:6.3` container) running the already-pure
  test subsets (~1,450 LOC in Pict, the P1 suites in Top Drawer). Zero product risk.
- Introduce PictKit's five seams ([06](06-pict-port.md)); land the Cairo/libpng
  backend with the ported math tests. macOS behavior stays byte-identical.
- De-risking prototypes to run *in this phase*, each ≤ a few days:
  1. gtk4-layer-shell from Swift: an anchored, always-on-top tab strip with a hover
     sliver on KDE or Sway (dexbar + WolfDan wrapper as references).
  2. `GtkDropTarget` from Swift: accept a Nautilus file drop with highlight
     (COPY+MOVE actions).
  3. WebKitGTK-6.0 from Swift: load a page, intercept a context menu, read
     `get_image_uri()` (silveran pattern).
  4. GlobalShortcuts portal round-trip via D-Bus on GNOME 50.
  5. resvg/librsvg: rasterize a Papirus no-viewBox SVG through the kept
     `scalable()` helper; compare against the macOS renders.
  If any of these fails, the plan changes *here*, cheaply.

### Phase 1 — Top Drawer core extraction (medium, benefits macOS directly)

- Extract `TabController`'s inlined policies (reconcile/park, de-overlap fold, drag
  magnetization + z-restack, spring-load/peek state machine, hotkey conflict
  handoff, watch keying) into a `TopDrawerCore` SwiftPM package with the existing
  tests moved over; migrate `ObservableObject`/`@Published` in shared types to
  Observation ([03](03-swift-on-linux.md)); split the few pure cores out of UI files
  (`MarkdownText`, `ColorHex` math, `ForeignFullScreen.covers` geometry).
- Introduce the `IconName` abstraction over SF Symbol names on macOS + start the
  ~300-symbol mapping table ([04](04-ui-frameworks.md)).
- Ship this as a normal macOS release to prove no regressions.

### Phase 2 — `pict` CLI + `topdrawerd` on Linux (medium)

- Pict CLI: store read/write, theme import, `.desktop` override sync.
- `topdrawerd`: the P3 seams implemented for Linux (GVolumeMonitor, inotify,
  GAppInfo/XDG trash, xbel + LocalSearch recents, SNI tray, portal hotkeys),
  persistence, D-Bus interface (introspection-XML-first).
- Runs headless under systemd --user; testable with `busctl` before any UI exists.

### Phase 3 — Layer-shell frontend (medium-large)

- GTK4 + cairo tabs/drawers on gtk4-layer-shell; covers Kubuntu, Sway/Hyprland,
  COSMIC, Mir at near-macOS fidelity. This is the *simpler* frontend and validates
  the D-Bus schema, DnD, hotkeys, and icon rendering end-to-end.

### Phase 3.5 (optional) — XWayland interim mode for stock GNOME (small)

Verification against Mutter source showed X11 clients under XWayland *can*
self-position and stay above Wayland-native windows on stock GNOME (see
[02](02-desktop-constraints.md) §XWayland). An interim mode — the layer-shell
frontend's windows opened via the X11 backend with `_NET_WM_STATE_ABOVE` — gives
stock-GNOME users visible, clickable, droppable edge tabs *before* the extension
exists. Known ceilings: no hover-reveal (only an always-mapped strip), no
XGrabKey-style hotkeys (portal instead), demotion under fullscreen, fractional-DPI
blur. Ship it only if it falls out of the GTK backend cheaply; don't invest in it.

### Phase 4 — GNOME Shell extension (large, ongoing tax)

- Thin GJS extension: positions the app's real windows (ddterm/DING pattern:
  `move_frame`/`make_above`/`stick` — normal window type, **not** DOCK, which
  Mutter demotes under fullscreen; `unmake_above()` before `make_above()`; match
  windows by `gtk_application_id` or own them via `Meta.WaylandClient`),
  pressure-barrier edge reveal, `Main.wm.addKeybinding` hotkeys, running-apps +
  monitor-identity feed over the same D-Bus interface.
- Precedents for the "extension requires a separately-installed daemon" shape on
  extensions.gnome.org: Syncthing Indicator, GPaste Integration (ddterm/DING bundle
  their companion apps only because those are GJS scripts; a compiled Swift daemon
  **cannot** be bundled in the extension zip — it ships in the deb, which is
  exactly our architecture and the review-guideline-sanctioned one).
- Enablement UX (verified): installing via the extensions.gnome.org browser flow
  enables immediately after a user-approved dialog; an extension dropped by a
  **.deb is not even discovered until the next login and is never auto-enabled**
  (`gnome-extensions enable` / Extensions app; session-mode force-enabling is
  distro-only). Plan the first-run experience around this.
- Budget it as a permanently maintained mini-project: one compatibility release per
  GNOME cycle (GNOME 51 lands Oct 2026).

### Phase 5 — Pict editor app on Linux (medium)

- GTK shell over the shared `IconEditorModel`, WebKitGTK picker, sets from local
  system themes first.

## Packaging & updates

| Channel | Role |
|---|---|
| **`.deb` + self-hosted apt repo** | Primary. Full host access (a launcher's job is spawning arbitrary host apps), apt carries updates (the Sparkle-replacement role), post-install can register autostart + the daemon's systemd user unit |
| **AppImage (+AppImageUpdate)** | Secondary, distro-agnostic; type2-runtime no longer needs libfuse2. Our existing GitHub-release updater logic carries over for this channel with `.AppImage` asset preference |
| **Snap / Flatpak** | **Not for Top Drawer**: strict Snap confinement cannot exec host binaries (classic confinement is the canonical exception but manually gatekept); Flatpak would need `flatpak-spawn --host` + `--filesystem=host` for everything — a sandbox-shaped channel for an app that wants no sandbox. Pict's editor has the same conflict (it writes host `.desktop`/icon files). Revisit only if the store split ever makes a sandboxed editor meaningful |
| **GNOME extension** | extensions.gnome.org (review; the daemon ships separately via the deb — the sanctioned shape per GNOME's review guidelines) |

Distribution note: GUI builds are glibc-dynamic (the musl static SDK forbids dynamic
linking and GTK is glibc — [03](03-swift-on-linux.md)); bundle or depend on the Swift
runtime libs. The `pict` CLI *can* be a single static binary.

## Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| GNOME extension review/maintenance tax (per-release breakage; another ESM-scale break possible) | Medium, recurring | Keep the extension thin (positioning/input only); all logic in the daemon; version-gate like Dash to Dock |
| SwiftCrossUI 0.x churn / DnD & WebView gaps on GTK | Medium | The `LinuxPlatformKit` C-interop layer is framework-independent; fallback is imperative use of the same in-tree Gtk module ([04](04-ui-frameworks.md)) |
| Swift toolchain lag on new Ubuntu LTS (26.04 unsupported at release; swiftly#532) | Low-Medium | Build in Docker against 24.04 toolchain; glibc forward-compat; distro `swiftlang` as fallback |
| Over-fullscreen drawer behavior on GNOME (extension tier) | Low-Medium | Mutter's stacking code says it works (`make_above` = layer TOP above ordinary fullscreen windows; no fullscreen layer exists) — verify empirically in the Phase 0 spike; worst case: drawer opens beside fullscreen |
| Extension enablement friction (deb install ⇒ next-login + manual enable) | Low | First-run flow deep-links the e.g.o page / Extensions app; daemon works headless meanwhile (tray + hotkeys via portal) |
| Monitor identity without EDID serials (Wayland client tier) | Low | Mutter-style (vendor, model, description) tuple; extension tier gets Mutter's own identity; existing unknown-UUID fallback already handles misses |
| `recently-used.xbel` coverage narrower than Spotlight | Low | Combine with LocalSearch + own RecentsStore (which already exists and is portable) |
| Aparoksha/rhx single-maintainer bindings | Low (if C-interop-first) | Wrap only what we use; vendored modulemaps are cheap to own |
| Wayland protocol drift (ext-foreign-toplevel spreading, GNOME policy changes) | Low | Capability-abstracted daemon API; frontends degrade per the matrix in [02](02-desktop-constraints.md) |

## What we give up, honestly

- **Stock-GNOME-without-our-extension** users get no dock — there is no engineering
  answer to this; only the extension, or their choice of desktop.
- Behind-window blur (`NSVisualEffectView`) → translucent flat color.
- The drag-pasteboard "peek while dragging anywhere" trick → reveal on
  sliver drag-enter instead.
- iCloud in the cloud tab → Dropbox/GDrive/OneDrive/rclone instead.
- SF Symbols → a mapped open icon set (visual identity shift on Linux).
- macOS-recorded hotkeys → re-record once on Linux.

## Verification appendix

Three clusters of load-bearing claims were adversarially re-verified after the main
research pass (2026-08-23), by agents instructed to *refute* them against primary
sources — reading swift-corelibs-foundation, swift-foundation, Mutter, and
gnome-shell source directly. Results are folded into the documents above; the
verdicts are recorded here so future readers know what was double-checked.

### 1. FoundationNetworking / Foundation API surface (source: corelibs `main` @ 761b621, swift-foundation @ 767ff1c)

| Claim | Verdict |
|---|---|
| `URLSession.bytes(for:)` works on Linux | **Refuted** — never existed in FoundationNetworking on any Swift version; not a stub, the symbol is absent ([#5401](https://github.com/swiftlang/swift-corelibs-foundation/issues/5401)) |
| async `data(for:)`/`download(for:)` on Linux | **Confirmed** — real implementations, but only since Swift 6.0 ([PR #4970](https://github.com/swiftlang/swift-corelibs-foundation/pull/4970)); `download` doesn't auto-remove its temp file |
| `URLProtocol` test stubbing on Linux | **Partially** — works via `configuration.protocolClasses` (stub first; corelibs' own test suite does this); `registerClass` alone never intercepts http(s) ([#4940](https://github.com/swiftlang/swift-corelibs-foundation/issues/4940)) |
| `URLSessionConfiguration.background` unavailable | **Confirmed** (`@available(*, unavailable)`) |
| `.applicationSupportDirectory` → `$XDG_DATA_HOME` | **Confirmed** (`FileManager+XDGSearchPaths.swift`; maps to the XDG root — apps append their own subdirectory) |
| `FileManager.trashItem(at:)` on Linux | **Refuted as "works"** — the API does not exist at all (compile error); no XDG-trash implementation in Foundation; `.trashDirectory` maps to `~/.Trash`, not the spec location |
| `Data.write(.atomic)` = temp + rename | **Confirmed, stronger**: `O_CREAT\|O_EXCL` temp in the destination dir, `fsync`, mode restore, `renameat(2)`; non-atomic fallback only on DOS filesystems |

### 2. The XWayland fallback on GNOME Wayland (source: Mutter `main` — `place.c`, `window-x11.c`, `window.c`, `meta-enums.h`, `workspace.c`; GNOME bugzilla 765739)

The draft's quick dismissal was **partially wrong**. Verified scorecard:
positioning **yes** (Mutter never auto-places DOCK/override-redirect X11 windows and
honors ConfigureRequest moves in the real multi-monitor layout); always-on-top
**yes, above Wayland-native windows** (one unified stack; ABOVE = layer TOP(4) over
NORMAL(2); X11 struts reserve work area desktop-wide); global hotkeys **no**
(XGrabKey receives nothing while a Wayland window is focused — closed NOTABUG by
design); edge-reveal **no via polling** (XQueryPointer blind over Wayland surfaces),
partial via a mapped X11 edge strip. Fractional/mixed-DPI has real blur/sizing bugs
(GNOME 50 defaults Xwayland native scaling on). Xwayland itself: no removal plan;
active investment; safe through the LTS horizon. Net: a usable interim tier for
visible click-driven tabs; dead for the invisible-agent behaviors.

### 3. The GNOME-extension architecture (source: gjs.guide review guidelines, ddterm source, Mutter `window.h`/`window.c`, gnome-shell `extensionSystem.js`/`extensionDownloader.js`, xdg-desktop-portal-gnome NEWS, Ubuntu packages)

Confirmed with corrections: extensions must not bundle compiled binaries (a Swift
daemon ships separately — the sanctioned shape; D-Bus daemon communication is
established practice rather than codified text); **GSConnect is the wrong precedent**
(it is self-contained GJS — the right precedents are Syncthing Indicator and GPaste
Integration; ddterm/DING bundle GJS-script companions); the ddterm positioning
pattern confirmed in its `wm.js` (`move_resize_frame`, `move_frame`, `make_above`,
`stick`, with the `unmake_above`-first quirk and async `gtk_application_id`
window-matching caveat); **make_above windows stack above fullscreen** (no fullscreen
layer in Mutter; DOCK-type windows are instead demoted under fullscreen — use a
normal window + make_above); GlobalShortcuts backend per Ubuntu confirmed (24.04:
46.x, absent, not backportable; 25.10: 49.0 present; 26.04: 50.0 present; probe by
calling `CreateSession`, not by interface presence); DnD onto extension-positioned
windows has no known compositor-level obstruction (standard `wl_data_device` path —
gate on an empirical test); enablement UX: e.g.o browser flow enables immediately on
approval, a deb-shipped extension is undiscovered until next login and never
auto-enabled.
