# Markdown notes editor: options and improvement plan

*Research date: 2026-08-24. This document plans the work; it does not change the current editor.*

## Summary

Top Drawer's notes surface should become a single, continuously editable Markdown view rather than switching between a plain `TextEditor` and a limited preview. The best route to the same editing experience on macOS and Linux is a small, locally bundled web editor embedded in **WKWebView** on macOS and **WebKitGTK 6.0** on Linux.

The recommended editor is a deliberately slim **Milkdown/Crepe** build (Milkdown + ProseMirror + remark), with a **CodeMirror 6 raw-source mode** as an escape hatch. Milkdown gives non-technical users a Typora-like WYSIWYG experience while keeping Markdown as the persisted format. CodeMirror protects advanced or unsupported Markdown and provides a substantially better source editor than a plain multiline text field.

This recommendation is conditional on a short spike passing the round-trip, focus, accessibility, startup, and bundle-size gates below. If Milkdown fails those gates, use CodeMirror 6 alone; do not build a rich-text editor from scratch.

## What is wrong today

The implementation in `MacDring/Drawer/DrawerView.swift` and `MacDring/Common/MarkdownText.swift` has several structural UX problems:

- Opening a note shows a preview; clicking it replaces the whole surface with an unrelated plain-text editor. The cursor cannot be placed directly in rendered content.
- Formatting has no toolbar, syntax highlighting, Markdown shortcuts, or discoverability.
- Preview and editing have different layout and line wrapping, so switching modes is visually disruptive.
- The preview is a line classifier, not a Markdown parser. It supports headings, simple bullets, task checkboxes, and a subset of inline syntax, but not ordered/nested lists, block quotes, fenced code, tables, thematic breaks, or other normal CommonMark/GFM constructs.
- Preview rendering uses a non-lazy stack and parses inline Markdown line by line. This is both incomplete and an avoidable performance risk for long notes (also recorded in `BACKLOG.md`).
- The floating **Done** button covers content and implies that edits are not already saved.
- A future Linux implementation using GTK `TextView` would produce another editor with different behavior, shortcuts, rendering, and bugs.

Useful behavior that must remain:

- Markdown remains plain text in `Tab.notes`; no data migration or proprietary document format.
- Changes persist automatically through `TabStore.setNotes`/its existing coalesced save path.
- Tabs and drawers remain non-activating panels and do not steal focus from the previously frontmost app.
- Task boxes can be toggled directly.
- Existing notes must never be silently damaged by opening or merely viewing them.

## Goals and non-goals

### Goals

1. One calm, directly editable surface: rendered structure remains visible while typing.
2. Friendly formatting controls and Markdown typing shortcuts.
3. Identical document semantics and near-identical interactions on macOS and Linux.
4. CommonMark plus the useful GFM subset: strikethrough, tables, autolinks, and task lists.
5. Reliable undo/redo, selection, spell checking, find, paste, IME, bidirectional text, and keyboard navigation.
6. Preserve source Markdown as the durable, exportable value.
7. Work offline with no CDN, telemetry, or network dependency.
8. Keep the host app authoritative for persistence, links, theme, and lifecycle.

### Non-goals for the first release

- Collaboration, cloud sync, AI writing features, comments, track changes, or arbitrary HTML.
- Image upload, remote-image rendering, attachments, or drag-reordering blocks.
- A full document-management window. Notes remain quick scratchpads in drawers.
- Pixel-identical native controls around the editor; document behavior is the shared part.

## Options investigated

| Option | Cross-platform consistency | User friendliness | Source fidelity | Integration/risk | Conclusion |
|---|---:|---:|---:|---:|---|
| **Milkdown/Crepe in WebKit** | High | High | Medium | Medium-high | **Recommended rich editor**, subject to spike gates |
| **CodeMirror 6 in WebKit** | High | Medium | High | Medium-low | **Recommended source mode and fallback** |
| ProseMirror + `prosemirror-markdown` directly | High | High after substantial work | Medium | High | Sound foundation, but recreates UI and plugins that Milkdown already supplies |
| Separate `NSTextView` and GTK `TextView`/GtkSourceView editors | Low | Medium | High | High long-term | Native feel, but duplicates formatting, highlighting, accessibility fixes, and test effort |
| Apple `swift-markdown` or `cmark-gfm` plus native views | Parser only | N/A | High | High for editing | Good parser choices, not editor widgets; they do not solve selection or rich editing |
| Monaco | High | Medium | High | High weight | Excellent code IDE, oversized and visually wrong for a scratchpad |

### Milkdown/Crepe

Milkdown is an MIT-licensed, plugin-driven WYSIWYG Markdown editor built on ProseMirror and remark. Its higher-level Crepe editor already provides editable task lists, links, lists, tables, a selection toolbar, a configurable fixed top bar, placeholders, and Markdown change callbacks. Features can be disabled or assembled with `CrepeBuilder`, which is important for keeping the bundle and UI small.

Why it fits:

- The editor's input and output are Markdown, not opaque HTML.
- The GFM preset covers task lists, tables, strikethrough, and footnotes on top of CommonMark.
- A rendered editable surface removes the current Edit/Preview mode switch.
- ProseMirror supplies mature transaction, history, command, selection, paste, and schema mechanisms.

Risks:

- Parse/serialize cycles normalize Markdown and cannot preserve every author's exact whitespace or equivalent syntax. Unsupported syntax may be transformed.
- `contenteditable` behavior, spell checking, accessibility, and IME must be tested in both WebKit implementations rather than assumed.
- Milkdown has a larger JavaScript dependency graph and more API churn than CodeMirror.
- Crepe's default feature set is too broad for Top Drawer. Image upload, LaTeX, AI, block dragging, and code-language search should not ship in the scratchpad.

Mitigation: use a pinned, audited, minimal build; retain raw-source mode; never serialize on open; and block release on corpus round-trip tests.

### CodeMirror 6

CodeMirror 6 is an MIT-licensed modular web editor with maintained Markdown language support. Its official feature set includes syntax highlighting, search/replace, undo history, accessibility, keyboard-only use, bidirectional text, spell-check-compatible editing, theming, and large-document performance.

It is the safest source-preserving option because the document remains text. A compact toolbar can apply Markdown syntax, and decorations can soften punctuation without changing it. It is not truly WYSIWYG, however, and users still need to understand some syntax. It therefore serves two roles:

1. an explicit **Source** mode for advanced content and recovery;
2. the complete fallback if the Milkdown spike does not pass.

### Native editors

An AppKit text system implementation could feel excellent on macOS, and GtkSourceView can provide highlighting, history, and search on Linux. The apparent dependency savings are misleading: Top Drawer would own two implementations of Markdown commands, cursor-safe delimiter insertion, themes, task interaction, parsing-to-style mapping, and every selection/IME bug. They also cannot provide a shared WYSIWYG document model. This is reasonable only if WebKit cannot coexist reliably with the non-activating drawer panels.

## Proposed experience

### Default rich mode

- The note opens exactly where it was left, already editable; no preview state and no **Done** button.
- Body text, headings, lists, quotes, links, code, and tasks render in place.
- Markdown shortcuts work naturally (`# `, `- `, `1. `, `- [ ] `, `> `, triple backticks), and Backspace at the start of an empty block returns it to a paragraph.
- A compact top bar exposes paragraph/heading, bold, italic, link, bullet list, numbered list, and task list. Less-used quote, code block, rule, table, and **Source** actions live in an overflow menu. The bar collapses responsibly in narrow drawers.
- Standard platform shortcuts use `Cmd` on macOS and `Ctrl` on Linux. Undo/redo operate on editor transactions, not host updates.
- Task boxes toggle in place. Links require an explicit open action (for example, Cmd/Ctrl-click or an **Open Link** tooltip) so an editing click never launches unexpectedly.
- Autosave is communicated subtly only when useful (for example, an error or unsaved state), not with a modal editing mode.
- Empty notes show a useful placeholder: “Write a note… Type / for blocks” only if the slash menu survives usability testing; otherwise omit the slash menu and mention Markdown shortcuts.

### Source mode

- Source mode uses CodeMirror with Markdown highlighting, line wrapping, find/replace, spell checking where supported, and the same theme/font metrics.
- Switching modes preserves logical selection when practical and at minimum restores the nearest block, rather than jumping to the beginning.
- If rich mode cannot represent a document safely, open it in source mode with a non-alarming explanation and an option to try rich mode on a copy.
- The last mode is transient per drawer session initially; it should not require a document schema change.

## Architecture

### Shared web asset

Create a small TypeScript package outside the Swift source tree, for example:

```text
EditorWeb/
  package.json
  package-lock.json
  src/
    editor.ts          # Milkdown/Crepe setup and command adapter
    source.ts          # CodeMirror source mode
    bridge.ts          # versioned host protocol
    theme.css
  tests/
  dist/                # deterministic, reviewed production artifact
```

Rules:

- Pin exact npm versions and commit the lockfile.
- Bundle all JavaScript, CSS, fonts/icons, and source maps needed for debugging; no runtime CDN.
- Generate a third-party license inventory in `dist/` and verify compatible licenses in CI.
- Build with only CommonMark/GFM, history, listener, task/list, link, toolbar, and required Crepe components. Disable image upload, AI, collaboration, LaTeX, remote fonts, and unnecessary code-block language bundles.
- Keep the generated bundle deterministic and add a CI check that rebuilding produces no diff.

### Host adapters

Define a platform-neutral `MarkdownEditorSession` contract in Swift, then implement:

- macOS: `WKWebView` wrapped for SwiftUI/AppKit and hosted inside the existing drawer panel;
- Linux: WebKitGTK 6.0 through the `LinuxPlatformKit` bridge already anticipated by the Linux-port research.

The bridge should be small and versioned:

```text
host -> editor: initialize(markdown, theme, platform, revision)
               replaceDocument(markdown, revision)
               focus(selection?)
               command(name)
               setTheme(theme)
editor -> host: ready(protocolVersion)
               changed(markdown, editorRevision)
               openLink(url)
               focusChanged(isFocused)
               diagnostic(code, detail)
```

Use revision IDs to distinguish local edits from host replacements and prevent feedback loops. The host remains the source of truth and calls the existing notes-change callback. Coalesce bridge traffic (roughly 150–300 ms while typing), flush immediately on focus loss/drawer close/application termination, and retain the current store's atomic/coalesced disk save behavior.

Only one drawer is open at a time, so keep one editor/web view alive and reset its session between notes if measurements show that this avoids visible cold-start latency. Do not let an old session write into a newly opened tab; use the same generation/token discipline already used by drawer and icon-editor callbacks.

### Markdown compatibility and data safety

Use **CommonMark + the selected GFM extensions** as the documented dialect. Build a checked-in corpus containing:

- all existing first-run Welcome note constructs;
- headings, nested ordered/unordered/task lists, emphasis combinations, links/autolinks, quotes, thematic breaks, inline/fenced code, tables, escaped punctuation, Unicode, bidi text, and CRLF input;
- malformed/incomplete Markdown users commonly leave while typing;
- raw HTML, reference links, footnotes, hard breaks, and other edge cases even if rich mode does not expose them.

Required behavior:

1. Opening and closing without editing must preserve the exact original string.
2. Rich editing may normalize syntax only after a real user transaction.
3. Supported documents must remain semantically equivalent after parse/serialize/parse.
4. Unsupported content must remain editable in source mode and must never be silently dropped.
5. Keep `Tab.notes` and the launcher JSON schema unchanged, so downgrade and export remain possible.

The spike must identify Milkdown's exact normalization behavior and produce an explicit support table before implementation is accepted.

### Security and privacy

A web view is an implementation detail, not a browser:

- Load only the bundled local editor document.
- Apply a restrictive Content Security Policy: deny network connections, frames, objects, media, and remote images; permit only the exact local script/style mechanism required by the bundle.
- Reject all navigation in the web view. Send validated `http`/`https` links to the host, which opens them through the normal external-browser path. Reject or explicitly handle every other scheme.
- Do not enable file URL access, clipboard APIs beyond editing needs, persistent website storage, service workers, developer extras in release builds, or arbitrary script injection.
- Pass Markdown as structured bridge data, never by interpolating it into HTML or JavaScript source.
- Do not render raw HTML in rich mode. Do not fetch remote images in v1.
- Use an ephemeral/non-persistent web data store where available.
- Add no telemetry. The editor must function with networking disabled.

## Delivery plan

### Phase 0 — UX and technical spike (throwaway production code)

Build a standalone local harness containing minimal Crepe and CodeMirror configurations, then embed it in both WKWebView and WebKitGTK.

Exit gates:

- no content loss across the compatibility corpus;
- correct typing and selection with VoiceOver and Orca smoke tests;
- keyboard-only toolbar/source-mode use;
- IME smoke tests (marked text, CJK composition, emoji), dead keys, bidi text, paste, spell check, and undo/redo;
- focus works from a non-activating macOS panel without activating Top Drawer or breaking the frontmost app;
- no network requests under an intercepting proxy;
- warm opening appears instantaneous and cold opening has no prolonged blank flash (record actual timings before setting the final budget);
- production bundle and incremental memory costs are measured and documented, not guessed;
- light/dark/high-contrast themes and 200% scaling remain legible.

Decision:

- Gates pass: proceed with minimal Milkdown rich mode + CodeMirror source mode.
- Rich mode fails but WebKit is sound: ship CodeMirror-only first.
- WebKit focus/accessibility is unsound: stop and write a native AppKit/GTK design based on the spike evidence.

### Phase 1 — Shared editor bundle and contract

1. Add the TypeScript package, lockfile, deterministic build script, license report, CSP, and bridge contract.
2. Implement rich/source modes with only the agreed feature subset.
3. Add JavaScript unit tests for commands, bridge revisions, mode switching, serialization, and hostile link/content inputs.
4. Add visual fixtures for narrow/wide, light/dark, empty, long, code-heavy, and deeply nested notes.

### Phase 2 — macOS integration

1. Add the WKWebView adapter and embed it in the notes branch of `DrawerView`/the AppKit hosting layer.
2. Preserve the current `DrawerModel.notes` and `onNotesChanged` boundary so persistence stays independent of the editor implementation.
3. Remove `notesPreview`, the **Done** overlay, and the custom `MarkdownText` UI only after feature parity and migration tests pass.
4. Keep pure task-toggle/line-ending tests where they still protect migration behavior; replace renderer classification tests with editor contract/corpus tests.
5. Manually verify non-activation, Spaces/fullscreen behavior, drawer close/reopen, outside-click dismissal, and app termination flushing in a real GUI session.

Phase 2 can ship on macOS before Linux, but the shared bundle and bridge must not contain macOS assumptions.

### Phase 3 — Linux integration

1. Reuse the exact `EditorWeb/dist` asset and protocol through WebKitGTK 6.0.
2. Add only a thin Linux web-view adapter; do not fork editor JavaScript or Markdown behavior.
3. Map Ctrl-based shortcuts, system font/theme/high-contrast preferences, external-link launching, and clipboard integration.
4. Test on the GTK frontend(s) selected by the Linux-port plan, including Wayland scaling and Orca.

### Phase 4 — polish and removal

- Compare telemetry-free local diagnostics and user feedback for accidental link opens, source fallback frequency, load failures, and save errors.
- Tune toolbar overflow and shortcuts; add localized labels before broad release.
- Remove the old renderer after one release with no fallback need. Until then, it may remain as a failure fallback, not a user-selectable third mode.
- Update `README.md`, `PLAN.md`, `BACKLOG.md`, and Linux-port documents when implementation decisions become final.

## Acceptance criteria

- A user can create headings, bold/italic text, links, bullet/number/task lists, quotes, code, rules, and supported tables without memorizing syntax.
- Markdown-aware users can type normal shortcuts and inspect/edit the source at any time.
- No Edit/Preview/Done mode dance remains.
- Existing notes are byte-identical after view-only open/close and cannot be lost when rich parsing fails.
- macOS and Linux persist equivalent Markdown for the shared corpus.
- Undo/redo, find, selection, paste, spell checking, IME, bidi text, screen-reader navigation, and keyboard-only controls pass the agreed matrix.
- The drawer remains non-activating on macOS.
- The editor makes zero network requests and rejects in-web-view navigation.
- Opening/closing and termination cannot lose the last debounced edit or apply an old edit to another tab.
- Bundle size, cold/warm startup, and memory measurements are published with the implementation PR and meet budgets chosen from the Phase 0 baseline.

## Sources

Primary sources consulted on 2026-08-24:

- [CodeMirror overview](https://codemirror.net/) — features, Markdown language support, accessibility claims, and MIT license.
- [CodeMirror Markdown language package](https://github.com/codemirror/lang-markdown) — official Markdown integration and license.
- [Milkdown repository](https://github.com/Milkdown/milkdown) — architecture (ProseMirror + remark), activity, and MIT license.
- [Milkdown Crepe API](https://milkdown.dev/docs/api/crepe) — feature flags, minimal builder, toolbar, tasks, tables, Markdown callbacks, and source retrieval.
- [Milkdown GFM preset](https://milkdown.dev/docs/api/preset-gfm) — GFM tables, task lists, strikethrough, footnotes, and CommonMark dependency.
- [ProseMirror Markdown example](https://prosemirror.net/examples/markdown/) — Markdown parser/serializer model and switching between source and rich views.
- [Apple swift-markdown](https://github.com/apple/swift-markdown) — cross-platform Swift parsing/building/editing/analyzing library; it is a document library, not a text-editor widget.
- [GitHub cmark-gfm](https://github.com/github/cmark-gfm) — CommonMark/GFM parser option, not an editing UI.
- [`docs/linux-port/04-ui-frameworks.md`](linux-port/04-ui-frameworks.md) — this repository's verified WKWebView/WebKitGTK and Swift-on-Linux integration research.
