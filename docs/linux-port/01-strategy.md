# 01 — Strategy: the option space, prior art, and the recommendation

*Findings as of 2026-08-23. Confidence markers: **[V]** verified against a primary
source, **[I]** reasonable inference, **[U]** unverified.*

## The four facts that dominate every option

1. **Ubuntu 26.04 LTS "Resolute Raccoon" (April 2026) ships GNOME 50 with a
   Wayland-only session.** The X11 GNOME session was dropped in Ubuntu 25.10 and the
   code removed upstream in GNOME 50; XWayland remains for legacy X11 *apps*, but no
   user can "log into Xorg" anymore. Ubuntu 24.04 LTS (GNOME 46, supported to 2029)
   is the last LTS with a selectable X11 session. **[V]**
   ([Ubuntu 26.04 release notes](https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/),
   [Ubuntu discourse on 25.10 dropping Xorg](https://discourse.ubuntu.com/t/ubuntu-25-10-drops-support-for-gnome-on-xorg/62538),
   [GNOME X11 removal FAQ](https://blogs.gnome.org/alatiera/2025/06/23/x11-session-removal-faq/))

2. **Wayland clients cannot position their own windows.** xdg-shell has no
   set-position, no keep-above, no global pointer reads — by design. GTK4 removed
   `gtk_window_move()` / `set_keep_above()` / `GtkStatusIcon` accordingly. The one
   protocol that *can* anchor surfaces to screen edges is **wlr-layer-shell**. **[V]**
   ([GTK 3→4 migration guide](https://docs.gtk.org/gtk4/migrating-3to4.html),
   [layer-shell protocol](https://wayland.app/protocols/wlr-layer-shell-unstable-v1))

3. **GNOME's compositor refuses layer-shell for third-party apps, deliberately and
   durably.** The upstream requests were closed within minutes-to-hours of filing in
   2019 and remain closed in 2026; GNOME's position is that shell components belong to
   GNOME Shell (extensions). KDE KWin, Sway/Hyprland/wlroots, COSMIC, and Mir all
   support layer-shell. Cairo-Dock — after completing a full Wayland port in 2025 —
   still ships with "GNOME Shell / Mutter, including the default Ubuntu desktop, is
   unfortunately not supported." **[V]**
   ([mutter#973](https://gitlab.gnome.org/GNOME/mutter/-/issues/973),
   [gnome-shell#1141](https://gitlab.gnome.org/GNOME/gnome-shell/-/issues/1141),
   [gtk4-layer-shell supported compositors](https://github.com/wmww/gtk4-layer-shell),
   [Cairo-Dock Wayland support](https://github.com/Cairo-Dock/cairo-dock-core/wiki/Wayland-support))

4. **Swift itself is a first-class citizen on Ubuntu.** Swift 6.3.3, official
   toolchains for 22.04/24.04, `swiftly` installer, Docker images, VS Code +
   SourceKit-LSP + lldb-dap. Throwing the Swift code away is a choice, not a
   necessity. **[V]** ([platform support](https://www.swift.org/platform-support/),
   details in [03](03-swift-on-linux.md))

The consequence of 1–3 cannot be over-stressed: **on stock Ubuntu, an edge-docked,
always-on-top launcher cannot be an ordinary application process — in any language or
framework.** Whatever we pick — Swift, Qt, Flutter, Rust, C — the dock either lives
inside GNOME Shell (as an extension) or the user isn't on stock GNOME.

---

## The options

### A. Shared Swift core (SwiftPM) + per-platform native UI

Keep the existing AppKit/SwiftUI apps on macOS untouched; compile the non-UI code on
Linux; write a new GTK4 UI layer for Linux.

- The `#if canImport(AppKit)` / protocol-seam idiom is well-established, and the
  strongest industrial precedent is **Arc on Windows** (The Browser Company): a Swift
  core shared with the Mac app, per-platform UI via a Swift/WinRT projection —
  documented on swift.org itself. **[V]**
  ([Swift Everywhere: Windows interop](https://www.swift.org/blog/swift-everywhere-windows-interop/))
- swift.org's ["Writing GNOME Apps with Swift"](https://www.swift.org/blog/adwaita-swift/)
  post is literally this architecture with the GTK side pre-built. **[V]**
- Realistic sharing (from the per-file inventory in [05](05-topdrawer-port.md) and
  [06](06-pict-port.md)): **Pict ~55–70%** of app LOC, **Top Drawer ~45%** of app LOC
  (P1+P2+P3 buckets — everything that isn't literally the AppKit/SwiftUI view layer),
  plus ~80% of both test suites. **[I]**

**Verdict:** proven, low-strangeness; the right answer for Pict and for Top Drawer's
*logic*. It does not by itself answer "how do I dock a window on GNOME" — that is
Option D's job.

### B. One cross-platform Swift UI (SwiftCrossUI)

[SwiftCrossUI](https://github.com/moreSwift/swift-cross-ui) (1.7k★, monthly releases,
v0.9.0 on 2026-08-19, backends for AppKit/UIKit/GTK4/GTK3/WinUI/Android) is the
healthiest Swift GUI project in this space and its SwiftUI-shaped API maximizes
conceptual sharing. But today, on the GTK backend: **no drag-and-drop** (open issue
[#546](https://github.com/moreSwift/swift-cross-ui/issues/546); the draft PR covers
AppKit only), **WebView is AppKit/UIKit-only**
([#148](https://github.com/moreSwift/swift-cross-ui/issues/148)), and there are no
window-positioning/keep-above/tray APIs (the backend protocol simply has none —
verified against `Sources/SwiftCrossUI/Backend/`). All gaps are fillable through its
sanctioned escape hatches (`GtkWidgetRepresentable`, `inspect`/`inspectWindow`) plus C
interop — a shipped app, [silveran-reader](https://github.com/kyonifer/silveran-reader),
embeds WebKitGTK exactly that way. **[V]**

**Verdict:** a credible *Linux UI layer* for the settings/editor class of window
(it is Option A with a nicer API), not a shortcut past Option A — and irrelevant to
the dock problem. Its pre-1.0 churn is real; re-evaluate as it matures.

### C. Full rewrite in a non-Swift stack (rejected)

Every full-rewrite stack was evaluated and every one loses on both axes at once: they
discard 100% of the Swift investment *and* still hit the GNOME wall for the dock.

| Stack | 2026 state | Why it loses |
|---|---|---|
| **Qt 6 / QML** | Mature; KDE's [LayerShellQt](https://github.com/KDE/layer-shell-qt) docks on KDE/wlroots | Still no GNOME docking; 0% Swift reuse; the Mac app would regress to a Qt app or fork into dual maintenance |
| **Flutter desktop** | Healthier than rumored — Canonical became lead maintainer / "Strategic Steward" of Flutter Desktop in the Flutter 3.44 announcement (May 2026) **[V]** ([flutter.dev](https://flutter.dev/blog/whats-new-in-flutter-3-44)); windowing APIs still experimental | Renders its own widgets, no layer-shell, Dart rewrite of everything |
| **Tauri v2** | Active; GTK3-based on Linux, so gtk-layer-shell is *reachable* (a real app ships that way) | Webview UI, Rust/JS rewrite, GNOME wall unchanged |
| **Electron** | XWayland by default, native Wayland rough, no layer-shell, GlobalShortcuts portal still an open feature request | Worst capability story for a dock; eliminate |
| **Kotlin Compose MP** | Desktop is JVM+Skia over AWT; no native Wayland (XWayland only); layer-shell an open request | Eliminate |
| **GNUstep** | **Verified dead end:** Swift on Linux has no ObjC runtime interop (`-enable-objc-interop` conflicts with Foundation on Linux; libobjc2's layout is incompatible with Swift's runtime contract) **[V]** ([swift#76247](https://github.com/swiftlang/swift/issues/76247), [libobjc2#306](https://github.com/gnustep/libobjc2/issues/306)) | Our apps are Swift, not ObjC — AppKit source compatibility buys nothing |
| **Darling** (run the Mac app) | Active project, but "most GUI applications unable to run fully"; no SwiftUI evidence | Verified not production-viable |

### D. Daemon + thin shell frontends (the GSConnect / ddterm pattern)

The architecture GNOME itself sanctions: a background service owning all logic,
exposing D-Bus interfaces, with a thin GNOME Shell extension as the presentation
layer inside the compositor — where edge-anchored, always-on-top, over-fullscreen
chrome, pressure-barrier edge reveal, compositor-side hotkeys, and true running-app
knowledge are all available.

Prior art, all verified:

- **GSConnect**: background service doing "all the heavy lifting", exposing D-Bus
  interfaces; a thin extension that "controls starting and stopping the service, and
  consumes the DBus interfaces" ([CONTRIBUTING.md](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/main/CONTRIBUTING.md)).
  (Nuance from verification: GSConnect's service is bundled GJS, not an external
  binary — it models the *service ⇄ D-Bus ⇄ extension split*; the precedents for an
  extension requiring a **separately installed** daemon on extensions.gnome.org are
  Syncthing Indicator and GPaste Integration. A compiled Swift daemon cannot be
  bundled in an extension zip — it ships in the deb, which is the sanctioned shape.)
- **ddterm**: an extension that positions and animates an *external GTK app's*
  window via Mutter APIs, with the app synchronizing over the extension's D-Bus API
  ([repo](https://github.com/ddterm/gnome-shell-extension-ddterm)).
- **Desktop Icons NG (DING)** — shipped by Ubuntu itself: extension + external GTK4
  app whose windows the extension pins; GTK4 port completed July 2026.
- **Window Calls** ([extension](https://extensions.gnome.org/extension/4724/window-calls/)):
  proves an extension can proxy window listing/moving/keep-above over D-Bus.
- GNOME's own review guidelines: extensions must not bundle binaries, but should
  "use D-Bus for communication with system services or external background
  processes" — a separately-packaged daemon is the sanctioned shape
  ([review guidelines](https://gjs.guide/extensions/review-guidelines/review-guidelines.html)).

Cost: a real GJS frontend (~2–5k LOC **[I]**) and the well-known per-GNOME-release
compatibility tax (the GNOME 45 ESM migration broke every extension once; since then
it is routine version-gating — Dash to Dock ships a compatibility release each cycle).
Benefit: **full dock capability on stock Ubuntu — the only option that retains it** —
and maximal Swift reuse, because everything below the presentation layer lives in the
shared daemon.

### What Linux docks actually did (the graveyard tour)

| Project | Stack | Fate |
|---|---|---|
| Plank | Vala/GTK3, X11-only | Frozen since ~2016; fork "Plank Reloaded" targets Cinnamon/X11 |
| Latte Dock | C++/Qt | Maintainer left 2022; unmaintained |
| Cairo-Dock | C/GTK | Revived 3.6 (Oct 2025) with layer-shell Wayland support — and explicit *no GNOME support* |
| nwg-dock | Go + gtk-layer-shell | Active; sway/Hyprland only, per-compositor forks |
| Dash to Dock / Dash to Panel | GJS extensions | The only dock lineage thriving on GNOME |

Lessons: every standalone dock either died with X11 or ported to layer-shell and
wrote GNOME off; the only dock form factor that thrives on GNOME is the extension;
Wayland docks need per-compositor window-list protocols anyway, so "one Linux dock
binary" was always a fiction. Keep the Linux frontends thin and the logic in the
shared core — thin frontends survive maintainer churn, fat ones die.

### Teams sharing a Mac app and a Linux app (architecture lessons)

- **Transmission**: shared C/C++ `libtransmission` core; fully native Cocoa macOS
  app; independent GTK and Qt clients; ~20 years of proof that a core-API split keeps
  the Mac app native while other frontends evolve.
- **Arc (The Browser Company)**: Swift core shared to Windows; UI as a serious
  per-platform sub-project.
- **GSConnect vs KDE Connect**: same protocol, two ecosystems — on GNOME,
  presentation-layer integration beats presentation-layer code reuse, so put the
  reuse *below D-Bus*.

---

## The recommendation

**Adopt D + A combined. Reject B as the primary bet (revisit for Pict's UI later).
Reject C entirely.**

1. **Phase 0 — PictKit on Linux** (details in [06](06-pict-port.md)): Linux CI, the
   raster/codec/watcher seams, store + resolver compiling on Ubuntu. Cheap,
   reversible, and every later phase depends on it.
2. **Pict for Linux — Option A**: shared PictKit + GTK4 UI + WebKitGTK picker +
   librsvg/resvg rasterization. Prototype the hard corners (editor grid, DnD) first.
3. **Top Drawer for Linux — Option D**: extract tab/drawer policies from the AppKit
   controllers into a shared core ([05](05-topdrawer-port.md)); ship a Swift daemon
   (systemd user service) owning tabs/stores/listers/persistence and exporting D-Bus;
   two thin frontends — gtk4-layer-shell (KDE/wlroots/COSMIC/Mir: near-macOS
   fidelity) and a GNOME Shell extension (stock Ubuntu). The extension is not the
   fallback; on Ubuntu 26.04 it is the only architecture that can actually *be*
   Top Drawer.
4. **Packaging**: `.deb` + apt repo primary, AppImage secondary; the GitHub-release
   updater logic we already have carries over for the tarball channel. Snap strict
   confinement cannot spawn arbitrary host apps (classic confinement is the canonical
   escape but gatekept); Flatpak would need `flatpak-spawn --host` for everything —
   both are sandbox-shaped channels for an app that wants no sandbox
   ([classic confinement](https://documentation.ubuntu.com/snapcraft/stable/explanation/classic-confinement/),
   [flatpak#5161](https://github.com/flatpak/flatpak/issues/5161)).

**Reasoning, one paragraph:** the decisive constraints are platform, not language.
Ubuntu's desktop is Wayland-only GNOME; GNOME refuses layer-shell; so every
"cross-platform app" framework is *equally* incapable of producing a real edge dock
there. The dock must live in the shell, therefore the reusable part of Top Drawer
must live below the UI — which Swift-on-Linux supports well, and which the
GSConnect/Transmission/Arc precedents validate at every scale. Pict has no such
constraint and takes the straight shared-core path. Both apps end up the same shape:
a Swift core shared with the Mac apps, thin platform-appropriate frontends.
