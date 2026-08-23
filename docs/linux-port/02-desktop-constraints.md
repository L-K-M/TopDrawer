# 02 — Desktop shell constraints: what a launcher may and may not do on Ubuntu

*Findings as of 2026-08-23. **[V]** = verified against a primary source, **[I]** =
inference, **[U]** = unverified. This is the document that shapes the whole port —
read it before the plans in [05](05-topdrawer-port.md).*

## Ubuntu releases in play

| Release | GNOME | Session reality |
|---|---|---|
| **24.04 LTS** (→2029) | 46 | Wayland default; **X11 session still selectable** — the last such LTS **[V]** |
| **25.10** | 49 | X11 Ubuntu session **removed**; Wayland only; XWayland retained **[V]** |
| **26.04 LTS** (Apr 2026, current) | 50 | **Wayland-only** — "GNOME Shell can no longer run as an X.org session"; XWayland retained **[V]** ([release notes](https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/)) |

Flavors: Kubuntu 26.04 = Plasma 6.6, Wayland default, X11 session not shipped;
upstream KDE removes X11 entirely in Plasma 6.8 (Oct 2026). Xubuntu 26.04 = Xfce 4.20,
still X11 by default (Wayland experimental via labwc/wayfire — which *do* support
layer-shell). KDE telemetry: >95% of Plasma 6.6 users on Wayland. **[V]**

## What a normal Wayland client cannot do

By protocol design (xdg-shell), a regular app cannot: position its windows at screen
coordinates, keep a window above others, read the global pointer, enumerate other
windows, or grab global keys. GTK4 removed the corresponding APIs
(`gtk_window_move`, `set_keep_above`, `GtkStatusIcon`). **[V]**
([GTK migration guide](https://docs.gtk.org/gtk4/migrating-3to4.html))

The exception is **wlr-layer-shell**: surfaces anchored to output edges with margins,
four layers (`background`→`overlay`), exclusive zones, per-output targeting, and
popup support. The spec places fullscreen windows "at the top layer", so an
**overlay-layer surface renders above fullscreen apps** — our reveal-over-fullscreen
behavior, for free. **[V]**
([protocol](https://wayland.app/protocols/wlr-layer-shell-unstable-v1))

### Compositor support matrix (wayland.app, tracked releases as of 2026-08)

| Compositor | layer-shell | wlr-foreign-toplevel (window list) | ext-foreign-toplevel-list |
|---|---|---|---|
| **Mutter (GNOME)** | **no** | **no** | **no** |
| KWin (KDE) | yes (v5) | no (own plasma-window-management) | no (at 6.6) |
| Sway / Hyprland / labwc / Wayfire / niri | yes | yes | mostly |
| COSMIC | yes | no (own protocol) | yes |
| Mir | yes | yes | yes |

**GNOME's refusal is deliberate and durable**: mutter#973 and gnome-shell#1141 were
closed on filing in 2019 and remain closed (with user comments as recent as July 2026).
Cairo-Dock 3.6 (Oct 2025), after a full Wayland port, ships with "GNOME Shell /
Mutter, including the default Ubuntu desktop, is unfortunately not supported." **[V]**

## Capability-by-capability

### Edge tabs: positioning + always-on-top + over-fullscreen

- **KDE / wlroots / COSMIC / Mir:** [gtk4-layer-shell](https://github.com/wmww/gtk4-layer-shell)
  (active, releases through 2025) gives us anchored, per-monitor, above-fullscreen tab
  surfaces. This tier is *near-macOS fidelity* — and layer-shell's anchoring makes
  Top Drawer's frame-defense (`defendFrame`) and foreign-fullscreen subsystems
  unnecessary. **[V]**
- **GNOME stock:** impossible for a client process. **[V]**
- **GNOME + our own Shell extension:** fully possible — the extension positions the
  *external app's real windows* via Mutter APIs (the
  [ddterm](https://github.com/ddterm/gnome-shell-extension-ddterm) pattern, also used
  by Ubuntu's own Desktop Icons NG), or draws chrome itself in St. Verified against
  Mutter source and ddterm's `wm.js`: `move_frame`/`move_resize_frame` (root
  coordinates), `make_above()`, `stick()`, `move_to_monitor()` are all public
  GJS-reachable API and used in production. **Over-fullscreen works by stacking
  math**: current Mutter has *no fullscreen layer* — a fullscreen app is an ordinary
  NORMAL(2) window, and a `make_above`'d window is TOP(4), so it stacks above
  fullscreen. Three verified traps: do **not** use the DOCK window type (explicitly
  demoted to BOTTOM when its monitor is fullscreen — the opposite of what we want;
  keep a normal window + make_above); `make_above` is ignored while the window is
  maximized; ddterm needs `unmake_above()` before `make_above()` (quirk documented
  in its source). Window matching keys off `gtk_application_id` (GTK apps exporting
  `org.gtk.Application`; a non-GTK window would need wm_class matching), arriving
  asynchronously after mapping on Wayland — the timing caveat to engineer around,
  or launch via `Meta.WaylandClient` for authoritative ownership as ddterm does. **[V]**

### Edge-reveal (pointer hits the screen edge)

- Global pointer reads are impossible for Wayland clients. **[V]**
- **Layer-shell tier:** the standard trick — keep a 1-few-px strip anchored on the
  `overlay` layer; pointer-enter on the strip = reveal. Works over fullscreen. **[I, standard practice]**
- **GNOME:** only via extension — `Meta.Barrier` pressure barriers (what GNOME's own
  hot corner and the [Hot Edge](https://github.com/jdoda/hotedge) extension use;
  works over fullscreen, suppression is opt-in). **[V]**
- Note: macOS-side, `TabController` also sniffs the *drag pasteboard* to peek
  concealed tabs during file drags. No Linux equivalent exists on any tier — drags
  are only observable when they enter our own surfaces. Feature needs a rethink
  (e.g. reveal on drag-enter of the sliver strip). **[V]**

### Global per-tab hotkeys

- **XDG Desktop Portal `GlobalShortcuts`** (portal 1.16+): KDE since Plasma 5.27,
  **GNOME since GNOME 48** (xdg-desktop-portal-gnome 48.rc NEWS: "Add global
  shortcuts portal backend"). Per-Ubuntu, verified against package versions:
  24.04 = 46.x → **absent, and not backportable via LTS updates**; 25.10 = 49.0 →
  present; 26.04 = 50.0 → present. Capability-check trap: on 24.04 the portal
  *frontend* still exposes the D-Bus interface — `CreateSession` just fails — so
  probe by calling, never by interface presence. UX: the portal shows a
  binding/approval dialog; the desktop remembers per-app-id. No GTK convenience
  API; libportal support is still an unmerged draft → speak raw D-Bus. **[V]**
  ([portal docs](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html))
- **GNOME 24.04 fallback / no-dialog route:** write
  `org.gnome.settings-daemon.plugins.media-keys custom-keybindings` via GSettings
  (combo + shell command like `topdrawer-cli toggle-tab <id>`); compositor-side, no
  dialog, but it edits user settings and can collide with user combos. **[I]**
- **GNOME + extension:** `Main.wm.addKeybinding` — compositor-side grabs, no dialogs. **[V]**
- **Sway et al.:** xdg-desktop-portal-wlr ships no GlobalShortcuts — compositor
  config only. **[V]**
- Migration note: persisted `HotkeySpec` values are Carbon keycodes + Carbon masks —
  they cannot be translated 1:1; plan a re-record (or ship a keysym mapping table)
  on first Linux run ([05](05-topdrawer-port.md)). **[V]**

### Running-app dot

- **GNOME stock:** Shell introspection D-Bus is allow-listed away since GNOME 41;
  fallback heuristics only (`/proc` + `.desktop` matching; GNOME launches apps into
  systemd scopes named `app-gnome-<appid>-<pid>.scope`, enumerable per user). **[V/I]**
- **GNOME + extension:** exact — `Shell.AppSystem`/`WindowTracker` (what the Dash's
  own running dots use), proxied over D-Bus
  ([Window Calls](https://extensions.gnome.org/extension/4724/window-calls/) proves the pattern). **[V]**
- **KDE:** plasma-window-management protocol (what Plasma's taskbar uses). **[V]**
- **wlroots:** wlr-foreign-toplevel-management / ext-foreign-toplevel-list. **[V]**

### Drag & drop from the file manager

GTK4 `GtkDropTarget` handles typed file drops with automatic `:drop(active)`
highlight styling; DnD onto layer-shell surfaces works on layer-shell compositors
(panels like waybar/Cairo-Dock accept drops). One real-world quirk: accept both COPY
**and** MOVE actions or Nautilus drops get rejected wholesale
([ghostty#11175](https://github.com/ghostty-org/ghostty/issues/11175)). On GNOME,
make the drop targets be the external app's real GTK windows (the extension positions
them) — DnD onto extension-drawn St chrome is unreliable territory. **[V/I]**

### Multi-monitor identity (ScreenAnchor's displayUUID)

- Wayland exposes `wl_output` name ("DP-1") + description (EDID make/model) — the
  full EDID serial never reaches clients. GTK's own source warns connector strings
  "should not be relied on as stable identifiers". Strategy: persist a
  (manufacturer, model, description, geometry) tuple — the same triple Mutter's own
  `monitors.xml` keys on — and treat connectors as hints. **[V]**
- Hotplug: `GdkDisplay::get_monitors()` is a `GListModel` with `items-changed` —
  maps cleanly onto `DisplayRegistry.onChange`. **[V]**
- The GNOME extension tier sees Mutter's EDID-based identity — *better* data than
  any client gets. X11 (RandR) exposes full EDID — best identity, dying session. **[V]**
- Port note: `EdgeLayout`'s math is Cocoa bottom-left-origin y-up; every consumer of
  stored fractional positions must go through one deliberate flip at the boundary
  ([05](05-topdrawer-port.md) §Surprises). Layout math measures against
  `visibleFrame`; the analogue is layer-shell exclusive zones / EWMH work area —
  using full output geometry would subtly shift every stored position. **[V]**

## The XWayland question

Could Top Drawer run as an X11 client under XWayland on stock GNOME? The
adversarial verification pass (Mutter source read directly — see the appendix in
[07](07-roadmap.md#verification-appendix)) corrected our first instinct to dismiss
this. The verified scorecard:

- **Positioning: yes.** Mutter never auto-places DOCK-type or override-redirect X11
  windows ("Assume the app knows best… leave them as-is", `place.c`), honors
  ConfigureRequest moves, and X11 coordinates map to the real multi-monitor layout
  (via one global integer scale factor; compute from XRandR geometry). **[V]**
- **Always-on-top: yes, above Wayland-native windows too.** Mutter keeps one unified
  stack: `_NET_WM_STATE_ABOVE` → layer TOP(4) above all NORMAL(2) windows regardless
  of client type; override-redirect is layer 7. X11 `_NET_WM_STRUT_PARTIAL` even
  reserves work area against Wayland windows. Caveat: DOCK-type windows are demoted
  below a fullscreen window on their monitor. **[V]**
- **Global hotkeys: no.** `XGrabKey` receives nothing while a Wayland-native window
  has focus — closed NOTABUG by design (GNOME bugzilla 765739). Portal instead. **[V]**
- **Edge-reveal: no via polling** (`XQueryPointer` is blind/stale over Wayland
  surfaces); **partial** via a permanently-mapped thin X11 edge strip with a strut
  (enter events do arrive over X11 surfaces), failing under fullscreen apps. **[V]**
- Fractional/mixed-DPI: blur, or (GNOME 50's now-default Xwayland native scaling)
  known sizing bugs at 125% etc. Xwayland itself is safe on Ubuntu through 2030+
  (only the X11 *session* died). **[V]**

**Verdict:** a genuinely usable *degraded* mode for a visible, click-driven dock on
stock Ubuntu — tabs that sit at the edge, stay above, accept clicks and XDND drops —
with the "invisible agent" behaviors (hotkeys-anywhere, hover-reveal, over-fullscreen)
dead. Worth considering as an *interim* stock-GNOME tier before the extension
exists; not the destination.

## The per-environment feasibility matrix

**A** = GNOME Wayland stock · **B** = GNOME + our extension · **C** = KDE Wayland ·
**D** = wlroots family (+COSMIC/Mir) · **E** = X11 sessions (Ubuntu 24.04 option,
Xubuntu, legacy)

| Capability | A | B | C | D | E |
|---|---|---|---|---|---|
| Edge tabs at exact position, chosen monitor | ❌ | ✅ | ✅ | ✅ | ✅ |
| Always on top | ❌ | ✅ | ✅ | ✅ | ✅ |
| Visible/revealable over fullscreen | ❌ | ✅ (make_above > fullscreen in Mutter's stack; verify empirically) | ✅ | ✅ | ⚠️ |
| Edge-reveal on pointer | ❌ | ✅ (barriers) | ✅ (overlay strip) | ✅ | ✅ |
| Global hotkeys | ⚠️ portal (25.10+), GSettings workaround | ✅ (no dialogs) | ✅ | ⚠️ | ✅ |
| DnD onto tabs | ❌ (no tabs) | ✅ (app-owned windows) | ✅ | ✅ | ✅ |
| Running-app dot | ⚠️ heuristics | ✅ exact | ✅ | ✅ | ✅ |
| Stable monitor identity | ⚠️ | ✅ (Mutter EDID) | ⚠️/✅ | ⚠️/✅ | ✅ |
| Survives desktop upgrades w/o work | ✅ | ❌ per-release extension tax | ✅ mostly | ✅ mostly | session dying |

## Bottom line

1. **A pure client app cannot be a DragThing on stock GNOME Wayland — policy, not a
   gap.** Every signature behavior is unreachable from an ordinary process.
2. **The only first-class path on stock Ubuntu is the hybrid Ubuntu itself uses**:
   thin GJS extension (positioning, keep-above, barriers, running-apps + monitor
   feed, hotkeys — all proxied over a private D-Bus interface) + the real app as an
   external process owning the actual tab/drawer windows, so DnD, rendering, and all
   logic stay in Swift. ddterm, DING, and Window Calls prove every piece in
   production. Costs: GJS code and a per-GNOME-release compatibility tax (routine
   since the one-time GNOME 45 ESM break; GNOME 51 lands Oct 2026).
3. **Everywhere else is easy mode** — one gtk4-layer-shell frontend covers
   KDE/wlroots/COSMIC/Mir at near-macOS fidelity; an X11 tier is optional legacy
   coverage through ~2029, not a foundation.
