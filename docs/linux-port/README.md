# Porting Top Drawer (and Pict) to Ubuntu Linux — Research

*Research completed 2026-08-23. All version numbers, package states, and project-activity
claims are as of that date; re-verify anything load-bearing before acting on it months later.*

This directory holds the findings of an in-depth investigation into the best way to
bring Top Drawer to Ubuntu, retaining as much of the Mac version's capability as
possible — including porting [Pict](https://github.com/L-K-M/Pict) — while sharing as
much code as possible with the Mac version.

## The one-paragraph answer

**Keep the code Swift, split it into a shared SwiftPM core, and give each platform a
thin native frontend.** Swift is a first-class citizen on Ubuntu (Swift 6.3.x, official
toolchains, VS Code/LSP/lldb — see [03](03-swift-on-linux.md)), and roughly **45–65% of
each app's code** can compile and run on Linux behind a handful of protocol seams.
What decides the architecture is not the language but the desktop: **Ubuntu 25.10+
ships a Wayland-only GNOME that deliberately refuses the layer-shell protocol every
third-party dock uses**, so on stock Ubuntu an edge-docked launcher cannot be an
ordinary application in *any* framework — Swift, Qt, Flutter, Electron, or C
([02](02-desktop-constraints.md)). The dock experience on GNOME must be delivered by a
thin GNOME Shell extension fronting a Swift daemon over D-Bus (the pattern GSConnect,
ddterm, and Ubuntu's own desktop-icons feature use), with a second, much simpler
gtk4-layer-shell frontend covering KDE and the wlroots world at near-macOS fidelity.
Pict has no such constraint: it ports as a conventional shared-core + GTK4-UI app, and
its store format is already platform-neutral ([06](06-pict-port.md)).

## The documents

| Doc | What it covers |
|---|---|
| [01 — Strategy & options](01-strategy.md) | The full option space (shared core, SwiftCrossUI, full rewrites, GNUstep, Darling, daemon+extension), prior art (Transmission, Arc, GSConnect, the Linux dock graveyard), and the recommendation with reasoning |
| [02 — Desktop constraints](02-desktop-constraints.md) | The Wayland/GNOME reality: what Ubuntu ships, what a client process may and may not do, the per-desktop feasibility matrix, hotkeys, running-app detection, edge reveal, multi-monitor identity, and the XWayland fallback verdict |
| [03 — Swift on Linux](03-swift-on-linux.md) | Toolchain and Foundation status: what works, what is absent (Spotlight, file-watching dispatch sources, Combine, ObjC runtime), URLSession specifics, libraries, packaging/distribution of Swift binaries |
| [04 — UI frameworks](04-ui-frameworks.md) | Swift GUI options on Linux (SwiftCrossUI, Adwaita for Swift, SwiftGtk, direct GTK4 C interop), a needs-vs-framework matrix, and shipped Swift-on-Linux apps to copy patterns from |
| [05 — Top Drawer port plan](05-topdrawer-port.md) | Codebase inventory (per-file portability buckets), the capability map (every tab kind and feature → its Linux equivalent), the target architecture, and the surprises a porting engineer must not miss |
| [06 — Pict port plan](06-pict-port.md) | PictKit's five seams, the editor plan (WebKitGTK, resvg/librsvg), what "shared icon store" even means on Linux, and why Pict's port is the natural first step (a fuller copy lives in the Pict repo as `docs/linux-port.md`) |
| [07 — Roadmap](07-roadmap.md) | Phased plan with de-risking prototypes first, effort estimates, packaging/update strategy, and a risk register |

## Headline findings

1. **Swift is not the risk.** Ubuntu 22.04/24.04 are fully supported platforms
   (Swift 6.3.3; official 26.04 toolchains still pending, with workarounds). The
   pure-Swift Foundation rewrite means FileManager, URL, JSON, UserDefaults,
   RunLoop/Timer, Process and friends genuinely work on Linux, and swift-crypto is a
   drop-in for our CryptoKit use.

2. **The desktop is the risk, and it is a policy wall, not a missing feature.**
   GNOME's compositor will not let a normal app place a window at a screen edge, keep
   it above others, read the global pointer, or enumerate running windows. Every
   surviving Linux dock either lives inside GNOME Shell as an extension or writes
   GNOME off entirely. This constrains Top Drawer's Linux shape more than every other
   finding combined.

3. **Everywhere that isn't GNOME is easy mode.** One gtk4-layer-shell backend gives
   KDE Plasma (Kubuntu), Sway/Hyprland/wlroots, COSMIC, and Mir edge-anchored,
   above-fullscreen, per-monitor tab surfaces — a close match for the macOS behavior,
   sometimes better (layer-shell makes the entire frame-defense and
   foreign-fullscreen subsystem unnecessary).

4. **The codebases are unusually well-prepared for this.** The test suites already
   isolate pure logic (~80–85% of Top Drawer's test LOC and most of PictKit's would
   run on Linux), listers and launchers already sit behind injectable seams, the JSON
   document formats are platform-neutral, and `FileManager`'s search paths map to XDG
   directories automatically on Linux.

5. **Every rewrite option loses on both axes.** Qt/Flutter/Tauri/Electron/Compose all
   hit the same GNOME wall for the dock *and* discard 100% of the Swift investment.
   GNUstep (no Swift↔ObjC interop on Linux) and Darling (GUI support rudimentary) are
   verified dead ends.

## Recommendation in brief

- **Phase 0 — PictKit on Linux.** Add Linux CI, introduce the raster/watcher seams,
  compile the store + resolver on Ubuntu. Cheap, reversible, and everything else
  builds on it.
- **Pict for Linux.** Shared PictKit + a GTK4 UI + WebKitGTK web picker + resvg/librsvg
  for SVG (which deletes the entire two-render WKWebView alpha-recovery subsystem).
- **Top Drawer for Linux.** Extract the tab/drawer *policies* out of the AppKit
  controllers into a shared core; ship a Swift daemon owning tabs, stores, listers,
  and persistence; front it with (a) a gtk4-layer-shell frontend for KDE/wlroots and
  (b) a thin GNOME Shell extension for stock Ubuntu, both speaking the same D-Bus
  interface.
- **Packaging:** `.deb` (+ apt repo) as the primary channel and AppImage as secondary;
  strict-confinement Snap and Flatpak are structurally wrong for a launcher that must
  enumerate and spawn arbitrary host apps.

See [07 — Roadmap](07-roadmap.md) for sequencing and the risk register.
