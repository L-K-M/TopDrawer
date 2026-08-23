# 04 — UI framework options for Swift on Linux

*Findings as of 2026-08-23. **[V]** = verified against a primary source (usually by
reading the project's actual source), **[I]** = inference, **[U]** = unverified.*

What the two apps need from a Linux UI layer:

- borderless/undecorated windows at exact coordinates on chosen monitors, always on
  top (the tabs + drawers) — *availability is compositor-bound, see [02](02-desktop-constraints.md)*;
- custom-drawn views (rounded tab pills, icon grids);
- drag-and-drop both ways, with drop-target highlighting (accepting Nautilus file
  drops is core to Top Drawer);
- popovers/context menus, normal settings windows, multi-window;
- an embeddable web view (Pict's picker) — WebKitGTK;
- a tray/status icon (menu-bar-item replacement).

## The candidates

### SwiftCrossUI ([moreSwift/swift-cross-ui](https://github.com/moreSwift/swift-cross-ui)) — the healthiest option

1,723★, monthly releases (**v0.9.0 published 2026-08-19**), funded org (moved from
stackotter to *moreSwift* in 2026), MIT. SwiftUI-*inspired* (deliberately not a
clone): `View`, `@State`, `WindowGroup`/`Window` scenes, `openWindow`. Backends:
AppKit (most complete), UIKit, **GTK4**, GTK3, WinUI, Android. Ships its own in-tree
`Gtk`/`Gtk3` wrapper modules (139 generated + ~27 manual widget files, GIR-based
generator) which are usable standalone. **[V]**

Verified against our needs (by reading the source at commit b835ea7):

| Need | Status |
|---|---|
| Window control | Backend protocol has create/size/limits/show/behaviors only — **no position, no keep-above, no decorations toggle, no monitor selection**. Escape hatch: `inspect`/`inspectWindow` hand you the underlying `Gtk.Window` (which has `isDecorated` etc.), and from there raw C. Positioning is then bounded by the compositor, not the framework **[V]** |
| Custom drawing | `Path`/Shapes/gradients at framework level; full cairo via `DrawingArea.setDrawFunc` in the Gtk module **[V]** |
| Drag-and-drop | **Missing on Linux.** Issue [#546](https://github.com/moreSwift/swift-cross-ui/issues/546); draft PR #547 is AppKit-only. No `GtkDropTarget`/`GtkDragSource` wrappers in the Gtk module. Fillable: `GtkWidgetRepresentable` + ~100 lines of C against GTK4's DropTarget/DragSource (which natively support file drops + `:drop(active)` highlight CSS) **[V]** |
| Web view | `WebView` exists **but only AppKit/UIKit implement it** ([#148](https://github.com/moreSwift/swift-cross-ui/issues/148)). Proven fill: [silveran-reader](https://github.com/kyonifer/silveran-reader) embeds WebKitGTK-6.0 via a `CWebKitGTK` systemLibrary + `GtkWidgetRepresentable`, incl. JS bridge and custom URI schemes **[V]** |
| Popovers/menus | Popover menus + `onTapGesture(.secondary)` (right-click) — workable **[V]** |
| Tray | None — StatusNotifierItem over D-Bus DIY (dexbar pattern) **[V]** |
| Multi-window, settings windows | Yes **[V]** |

Risks: pre-1.0 API churn (real, between 0.x releases), sparse docs, and DnD/webview
are *our* code until upstream lands them.

### Adwaita for Swift ([aparoksha/adwaita-swift](https://codeberg.org/aparoksha/adwaita-swift), ex-david-swift)

The swift.org-blessed GNOME framework
([Writing GNOME Apps with Swift](https://www.swift.org/blog/adwaita-swift/), 2024) with
a shipped Flathub app (Memorize) and a first-class Flatpak toolchain (Freedesktop SDK
Swift extension). Actively maintained (commits 2026-08-21) but rehomed twice
(GitHub → git.aparoksha.dev → Codeberg), single primary author, deps pinned to
`main` (no semver). Verified from the clone: polished declarative API and libadwaita
widget coverage, **but no DrawingArea/cairo, no DnD, no WebView, and even less window
control** than SwiftCrossUI. **[V]**

Fit: lovely for a from-scratch GNOME-HIG app; for our two apps every hard requirement
would be hand-written C anyway. A candidate for Pict's *editor UI* if we want the
libadwaita look and accept the gaps; not for Top Drawer.

Do not confuse with **[makoni/swift-adwaita](https://github.com/makoni/swift-adwaita)** —
a separate, *imperative* Swift 6 GTK4/libadwaita wrapper (created 2026-03, 8★, solo
author) which is the only Swift wrapper shipping DnD (`DropTarget`), cairo drawing
(`CairoContext`), *and* a WebKitGTK-6.0 product out of the box. Too young to bet on;
excellent to steal patterns from. **[V]**

### rhx/SwiftGtk (gir2swift ecosystem)

The most complete API surface (generated from the full GIR: GTK 3.22–3.24 and
4.0–4.22, SwiftCairo/SwiftPango/SwiftGdk companions), still maintained (gtk4 branch
commit 2026-05-04) by essentially one academic. Costs: 300k+ lines of generated code
(slow builds), GObject-flavored ergonomics, no release discipline. Its **gtk3 branch
is the only wrapper still exposing `gtk_window_move` + keep-above** (X11/XWayland
semantics) — relevant only to a legacy-X11 tier. **[V]**

### Direct C interop with GTK4 (no wrapper)

Fully practical and proven — 13 repos found doing exactly this, including
[dexbar](https://github.com/SucculentGoose/dexbar) (Swift, GTK4 C bindings,
**gtk4-layer-shell**, StatusNotifier tray via libdbusmenu, libsecret — i.e. the exact
Top Drawer Linux ingredient list, shipped end-to-end at small scale). Gotchas are
mechanical: a C shim for `g_signal_connect` varargs, pointer casting. This is the
*only* layer at which the dock's window mechanics can be implemented regardless of
which wrapper sits above it. **[V]**

### Dead ends (verified)

- **Qt from Swift**: qlift (Qt5) dormant for years, qlift6 dead since 2023, no
  KDE-backed bindings exist. Qt itself would be a fine dock toolkit (LayerShellQt) —
  there is just no living Swift bridge. **[V]**
- **Tokamak**: archived 2026-01-28. **[V]**
- **Slint**: no official Swift bindings (community WIP only). **[V]**
- **Shaft** (Swift Flutter-port, SDL3+Skia): impressive trajectory, very active, but
  owns its whole rendering stack (non-native), no webview, wrong shape for a dock.
  Watch-item only. **[V]**
- SkiaKit/VertexGUI/Suit: drawing-only or dormant. **[V/I]**

## Supporting libraries for the platform kit

| Concern | Library (all plain C, all packaged in Ubuntu) |
|---|---|
| Edge-anchored surfaces on Wayland | **gtk4-layer-shell** (active; works on KWin/wlroots/COSMIC/Mir; *not* GNOME — see [02](02-desktop-constraints.md)); tiny Swift wrapper prior art exists (WolfDan/SwiftGtk4LayerShell) **[V]** |
| Web view | **webkitgtk-6.0** (GTK4 + libsoup3; Ubuntu 24.04 ships 2.52.x). Context-menu interception via the `context-menu` signal + `WebKitHitTestResult.get_image_uri()` — *better* than our `willOpenMenu` hack; JS bridge is the same `window.webkit.messageHandlers.*.postMessage` API as WKWebView **[V]** |
| Tray | **StatusNotifierItem over D-Bus** (GtkStatusIcon removed in GTK4; libayatana has no GTK4 support). Ubuntu preinstalls and enables the AppIndicator extension, so SNI works on stock Ubuntu **[V]** |
| 2D raster (icons) | **Cairo** (ARGB32 premultiplied — same model as CG) + **gdk-pixbuf** (PNG/ICO decode; note its ICO loader can't read PNG-compressed entries — a ~100-line container splitter fixes favicons) + **librsvg** (SVG→Cairo) or **resvg** (Rust with an official C API) **[V]** |
| SF Symbols replacement | SF Symbols **legally cannot ship on Linux** (Apple license restricts to Apple-OS UIs) **[V]**. Alternatives: GNOME icon-development-kit (CC0, native look), Material Symbols (Apache-2.0, best coverage + weight axis), Phosphor (MIT, 6 weights), Lucide (ISC), Tabler (MIT, 6k+). Strategy: an `IconName` abstraction on macOS now, plus a hand-curated mapping table for the ~300 symbols we actually use (`SymbolPickerView`'s curated list is the inventory) |
| D-Bus | GDBus via GLib (boring, safe), or pure-Swift [wendylabsinc/dbus](https://github.com/wendylabsinc/dbus) (SwiftNIO, async/await, object export + codegen from introspection XML; young) **[V]** |

## Shipped Swift-on-Linux desktop apps worth studying

1. **Memorize** — first Adwaita-for-Swift app on Flathub; the Flatpak packaging template. **[V]**
2. **silveran-reader** — *exactly Pict's architecture*: shared Swift core ("SilveranKit"),
   Apple app with WKWebView, Linux app on SwiftCrossUI + direct WebKitGTK-6.0 C
   interop, Android/Kotlin. Copy its `CWebKitGTK` + `GtkWidgetRepresentable` bridge. **[V]**
3. **dexbar** — *exactly Top Drawer's ingredient list*: shared Swift core, macOS
   SwiftUI menu-bar app + Linux GTK4-C frontend with gtk4-layer-shell, SNI tray,
   libsecret. **[V]**

Nobody has shipped a *dock* in Swift — but every individual ingredient has Swift
prior art; only the union is novel. **[I]**

## Recommendation

**SwiftCrossUI (GTK4 backend) as the Linux UI base for conventional windows, plus a
hand-rolled `LinuxPlatformKit` C-interop module** for the five gaps (DnD bridge,
WebKitGTK view, SNI tray, layer-shell window setup, monitor enumeration via
`gdk_display_get_monitors`). Rationale: momentum + SwiftUI-shaped API (maximum
conceptual sharing with the Mac code) + sanctioned escape hatches with shipped proof.
Fallback if 0.x churn bites: drop to the same C-interop layer with SwiftCrossUI's
in-tree `Gtk` module used imperatively — the platform kit is identical either way,
which is what makes this choice low-regret. For Top Drawer's GNOME frontend the
framework question is moot (GJS extension, [02](02-desktop-constraints.md)); for its
layer-shell frontend the tabs/drawers are mostly custom-drawn cairo surfaces where
the framework matters least.
