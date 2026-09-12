# EditorWeb — shared Markdown editor bundle

The web asset behind the notes tab, per
[`docs/markdown-editor-improvement-plan.md`](../docs/markdown-editor-improvement-plan.md).
One bundle, two hosts: WKWebView (macOS) and WebKitGTK 6.0 (Linux). Markdown in,
Markdown out; the host app stays authoritative for persistence.

## Modes

- **Rich** (`src/editor.ts`) — a slim Milkdown/Crepe assembly via `CrepeBuilder`:
  toolbar, top bar, task lists, tables, link tooltip, placeholder, code fences.
  Image upload, LaTeX, AI, and the slash menu are excluded and tree-shaken out.
- **Source** (`src/source.ts`) — CodeMirror 6 with Markdown highlighting,
  wrapping, history, and search. Byte-exact by construction; also the recovery
  path for documents rich mode cannot represent.

## Shipping layout and host contract

`dist/` is the complete payload:

```
dist/editor.html    the page a host loads
dist/editor.js      the bundle
dist/editor.css
```

A host application:

1. loads `editor.html` with read access limited to that directory (on macOS,
   `WKWebView.loadFileURL(_:allowingReadAccessTo:)` scoped to `dist/`; a
   `WKURLSchemeHandler` serving only those three files, under a real origin,
   would be tighter still);
2. injects nothing: the page carries its own strict CSP (`default-src 'none'`,
   `connect-src 'none'`, no inline script) and no network access;
3. sends host messages with `evaluateJavaScript("window.topdrawerEditor.handleMessage(<json>)")`;
4. receives editor messages through the `topdrawer` message handler, which is
   the same JS API on WKWebView and WebKitGTK;
5. keeps the web view non-activating and out of the responder chain for
   activation purposes, per the app's existing panel rules.

`window.topdrawerEditor` only exists once the page has run, so a host should
wait for the editor's `ready` message before sending `initialize`.

## Bridge protocol (`src/bridge.ts`)

```
host -> editor: initialize(markdown, theme, platform, revision, documentID)
               replaceDocument(markdown, revision)
               focus()
               flush()
               command(toggleMode | undo | redo)
               setTheme(theme)
editor -> host: ready(protocolVersion)
               changed(markdown, editorRevision, documentID)
               openLink(url)
               focusChanged(isFocused)
               diagnostic(code, detail)
```

Host → editor travels through `window.topdrawerEditor.handleMessage(json)`;
editor → host through `window.webkit.messageHandlers.topdrawer.postMessage(...)`,
the same JS API on WKWebView and WebKitGTK.

Data-safety invariants (enforced in `src/session.ts` and `src/editor.ts`,
covered by tests):

1. `changed` fires only after a local user edit, and names the document it belongs
   to, so the host can save it against that note rather than whichever tab is open
   when it lands (an edit can arrive after a drawer closed or moved on). Rich mode additionally gates
   on a real interaction (key, IME, paste, drop, toolbar click) because Crepe
   applies its parsed document in a transaction *after* mount: reporting that
   would rewrite an untouched note with remark's normalization (`-`→`*`,
   `---`→`***`) just because it was opened.
2. Host replacements with an older revision than the last applied one are
   dropped (a late flush from a previously open tab) and reported; an
   identical retry at the same revision is ignored rather than forcing a
   remount.
3. Edits coalesce over a 200 ms window (`src/coalescer.ts`) and flush
   immediately on blur, drawer close (`visibilitychange`), `pagehide`, or
   explicit `flush()`.
4. Only `http(s)` links reach the host; other schemes are blocked inert. Anchors
   inside the document are intercepted, so a click never navigates the web view.
   Opening is explicit: Cmd/Ctrl-click hands the URL to the host, which opens it
   in the default browser. A plain click just moves the caret.
5. Applying a host document discards an edit still in flight (the host is
   authoritative for the note) and reports `edit-superseded`, so the loss is
   observable. Which side should win on a real conflict is a Phase 2 decision.
   A revision is recorded only after its document has mounted, so a failed apply
   can still be retried by the host.

## Build & test

```bash
npm ci            # pinned, lockfile-committed
npm run build     # deterministic esbuild bundle → dist/ (committed)
npm test          # vitest: corpus round-trip, session discipline, coalescer, protocol
npm run check     # tsc --noEmit
npm run smoke     # Playwright: harness gates, shipped-page gates, timings, memory
```

`dist/editor.js`, `dist/editor.css` and `dist/editor.html` are committed on
purpose: they are the reviewed production artifacts the apps load.
`LICENSES.md` is written by the build from the esbuild metafile, so the
inventory cannot drift from what ships. Source maps and `dist/meta.json` are
build-local and gitignored (they embed third-party sources and would swamp
review diffs). The `EditorWeb CI` workflow rebuilds from the lockfile and fails
on any diff against the committed artifacts.

## Harness

`harness/index.html` simulates the native host in any browser: corpus loader,
theme/mode/undo/redo toggles, bridge traffic log, and a network-request counter
that must stay at 0. Serve the package root and open it:

```bash
npx serve .     # or any static server; file:// works too
# → http://localhost:3000/harness/
```

The harness runs under a strict CSP with no inline script, mirroring the policy
the shipped page gets. That is what makes the `hostile` corpus a real test:
escaped markup must render inertly, and it fails loudly rather than executing.

`npm run smoke` covers both documents: the harness (controls, corpus, links,
hostile input) and `dist/editor.html` loaded the way a host loads it, with the
`window.webkit.messageHandlers.topdrawer` transport installed so the shipped
path is exercised. It also reports page load, mount and warm-reopen timings and
the heap cost of repeated document swaps, none of which a native host can be
asked for without a GUI session.

## Spike measurements (Phase 0)

- Bundle: **editor.js 1.48 MB minified (493 KB gzip)**, editor.css 30 KB,
  deterministic across rebuilds. Largest inputs: `@codemirror/lint` and
  `lodash-es` (both Crepe-internal), Vue runtime (Crepe components). KaTeX, the
  AI providers, and `@codemirror/language-data` are tree-shaken out. The bundle
  is built with `process.env.NODE_ENV=production`; the single remaining
  `process.env` reference is a short-circuited `typeof process < "u"` guard in
  the Lezer parser and cannot throw in a web view.
- Two versions of `@codemirror/state`/`view` ship (Crepe's own range plus this
  package's pinned direct dependency). Harmless but duplicated; slimming the
  direct dependency, or letting Crepe's version win, is a Phase 2 item.
- Compatibility caveat: Crepe's stylesheets use `color-mix()` (WebKit 16.2+).
  macOS 13.0 shipped WebKit 16.1, which predates it; later 13.x releases ship
  newer WebKit. Confirm on a 13.0 system, then either raise the notes editor's
  minimum or ship `color-mix` fallbacks. `:has()` is fine (Safari 15.4+).
- Timings and memory, measured by `npm run smoke` in `EditorWeb CI` (headless
  Chromium, `ubuntu-latest`, assets over loopback, page clock rather than
  Playwright round trips): page load 108 ms, mount after `initialize` 52 ms,
  warm reopen (reload plus `initialize`) 16 ms. Heap 9.0 MiB after the first
  mount and +1.7 MiB after ten document swaps, both sampled after a forced GC,
  so roughly 175 KiB survives each mount/destroy cycle. Small enough not to
  look like a leak, but it is not nothing, and the in-app figure is the one that
  matters. These are browser-side numbers from a different engine and a faster
  machine class than the drawers' target: treat them as an order of magnitude
  and a leak check, not as the WKWebView budget.
- Load path: `dist/editor.html` mounts and completes the handshake from a
  `file://` URL with the strict CSP intact and zero violations, so a host that
  scopes read access to `dist/` does not need a custom scheme to work. This is
  Chromium's answer; WKWebView's `'self'` handling for file documents may
  differ, so confirm it in the Phase 2 session, and prefer a custom scheme if
  it does not hold.
- Normalization behavior: see [SUPPORT.md](SUPPORT.md), regenerated by
  `npm run gen:support` (and by any full `npm test`). CI fails if the
  committed copy differs from what the sources produce.
  Load is always side-effect-free; a first real edit normalizes `-`→`*`
  bullets, `---`→`***`, bare URLs→`<url>`, and re-escapes unclosed syntax.
  One measured caveat: raw HTML and images are kept as *literal text* rather
  than nodes (`src/sanitize.ts`), because Milkdown's HTML parser builds real
  DOM elements from raw HTML and an `<img>` attempts a fetch. That protects the
  zero-network and no-permission promises at the cost of remark escaping them
  (`<div>` → `\<div>`, `![a](u)` → `!\[a\]\(u)`) on the first edit; content is
  preserved and converges after two passes. A byte-exact inert node view, and
  rendering local/data images, are Phase 2 work.

Remaining Phase 0 gates needing a real GUI session: WKWebView focus from a
non-activating panel (macOS), WebKitGTK embedding (Linux), IME/spell-check,
VoiceOver/Orca, cold/warm open timings in-app. The Playwright smoke test
(`npm run smoke`) covers boot, handshake, debounced typing, mode and theme
switching, and the zero-network gate in a real browser engine.
