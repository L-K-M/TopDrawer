# 06 — Pict port plan (summary)

*The full Pict research and plan lives in the Pict repository as
[`docs/linux-port.md`](https://github.com/L-K-M/Pict/blob/main/docs/linux-port.md).
This is the summary Top Drawer's plan depends on. Findings as of 2026-08-23.*

## Why Pict comes first

Top Drawer's icon ladder consults PictKit (rungs 3–4), and the Linux daemon wants
the same shared store. PictKit is also the *cheapest meaningful start* on the whole
Linux effort: the store is JSON+PNG files (inherently portable), the artwork math is
already test-proven through CG-free pure inits, and the package compiles on Linux
after five well-defined seams — no UI framework bet required.

## The reframing

Pict exists to undo macOS 26's icon masking; **Linux has no masking**, but it has
something better: spec-blessed, update-surviving mechanisms for overriding any app's
icon system-wide (per-app `.desktop` shadowing in `~/.local/share/applications`, and
generated user icon themes). A Linux Pict is therefore a *first-class desktop
customization tool*, not a workaround — with the JSON+PNG store as source of truth,
consumers (like Top Drawer's Linux frontends) reading it directly, and Pict keeping
the `.desktop`/theme override files in sync via the ported store watcher.

## The five PictKit seams

1. **Raster/codec** — `PixelImage` + codec protocol replacing `CGImage`; Cairo
   (same premultiplied-ARGB32 model as CG) + libpng/gdk-pixbuf backend; the one new
   piece of real work is reimplementing the normalizer's baked drop shadow (Cairo
   has no `setShadow`).
2. **Display image** — `IconResolver`'s `NSImage` is built in one place; make the
   output type generic.
3. **Watcher** — FSEvents → inotify (~100 LOC). Traps: no `IgnoreSelf` equivalent
   (tag-and-filter own writes); can't watch a not-yet-existing directory (watch the
   parent).
4. **Artwork provider** — `BundleArtwork` (the only file with no Linux meaning) →
   freedesktop icon-theme lookup behind `ArtworkProviding`.
5. **Launcher** — `PictURL`'s NSWorkspace calls → `xdg-mime`/`xdg-open` + a
   `.desktop` scheme handler.

Load-bearing invariants that must survive: FNV-1a filename digests byte-identical;
`.atomic` writes as rename (verified: Linux corelibs does temp+`rename(2)`);
`IconSourceMode` trap (`systemDefault` → `.system` on Linux disables the whole
ladder — consumers must pass `.originalPlusCustom`); main-queue delivery contracts
need a drained main loop; the entire filename/symlink/byte-cap security posture.

## The editor, in one table

| Subsystem | Port decision |
|---|---|
| SVG rasterizer (two-render WKWebView alpha hack, ~380 LOC) | **Delete**; librsvg or resvg (C API) render straight to RGBA. Keep the ~260 LOC of pure helpers (`isSVG`, viewBox synthesis — still needed for Papirus-style no-viewBox icons). Re-establish the no-network CSP intent in renderer terms; bump `renderVersion` |
| Web picker (WKWebView + JS bridge + `willOpenMenu` race workaround) | **WebKitGTK 6.0, near-1:1 and sometimes better**: `context-menu` signal hands over the hit-test result synchronously (`get_image_uri()`); the same `window.webkit.messageHandlers` JS API; copy silveran-reader's C-interop bridge |
| Icon sets (`tar` + GitHub tarballs of Linux themes) | Content is Linux-native; **GNU tar needs `--wildcards`** where bsdtar treated trailing args as patterns (real silent-failure bug); on Linux also read locally installed themes from `/usr/share/icons` — no download needed |
| Networking | `data(from:)`/`download(for:)` work on Linux (Swift 6.0+); **`bytes(for:)` has never existed on Linux** — port `RemoteIconFetcher` to a delegate task or AsyncHTTPClient, preserving the byte-count cap; URLProtocol test stubs port if injected via `configuration.protocolClasses` (`registerClass` alone never intercepts) — all verified against corelibs source |
| App enumeration | `g_app_info_get_all()` over `$XDG_DATA_DIRS/applications` (snap rewrites `Icon=` to absolute paths; Flatpak exports are theme-resolvable) |
| Editor UI (~2k LOC SwiftUI) | Rewrite on SwiftCrossUI/Adwaita + C-interop for DnD and the web view ([04](04-ui-frameworks.md)); `IconEditorModel` is deliberately view-free and ports after extracting `NSOpenPanel`/`NSImage` |

## Sequence

1. Linux CI running the already-pure test subset (~1,450 LOC runs unmodified today).
2. The five seams + Cairo backend, macOS behavior byte-identical.
3. **`pict` CLI on Linux** (store read/write, theme import, `.desktop` override
   sync) — proves the stack end-to-end, gives Top Drawer's daemon its icon source,
   and is buildable with the static Linux SDK.
4. The GTK editor app.

Shareable: **~55–70% of app LOC** plus effectively all of PictKit; the biggest
single subsystem (the WKWebView rasterizer) is deleted, not ported.
