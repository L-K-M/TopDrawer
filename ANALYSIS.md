# Top Drawer: remaining review findings

This backlog consolidates several repository reviews, including the MiMo pass. It covers the macOS app and the experimental Linux port. The working scale is one desktop user, dozens of tabs, hundreds of launchers, and occasional large or remote folders. Start with layout recovery, ambiguous identities, and failures that affect user files. Treat appearance and feature proposals as prototypes with the validation described in each entry.

The latest pass reviewed main at `c905100` and inspected the current AppKit and SwiftUI paths, persistence, live listings, shared models, Linux volume parsing, tests, and the supplied screenshot. The combined changes passed 636 macOS tests. The Linux volume fixes passed the focused volume suite in a Swift 6.3 Noble container. Performance claims without results are hypotheses. Live multi-display, Spaces, VoiceOver, compositor, and Instruments checks remain to be run. EditorWeb is a standalone harness; its runtime was outside this pass.

An Opus 5.5 pass on 2026-11-18 read main at `dd30c16` directly (tabs, drawer, controller, Settings, status menu) and ran seven LongCat 2.5 subsystem reviews. A second LongCat pass judged every finding adversarially, and each surviving one was re-read against the code. Its entries cite files and lines at that commit. Behavior marked as checked on device ran against an isolated home directory (see "Notes for future passes"). PR #220 then moved hotkeys, updates and color helpers into the shared Keycap, Updraft and Livery packages; entries it resolved are listed under "Resolved on main", and entries whose code it moved say where the fix now belongs.

## Implementations in review

The implementation branches below are open for merge. Revisit the underlying findings if a PR closes without landing.

- Distinguish an unreadable linked folder from an empty one. [PR #186](https://github.com/L-K-M/TopDrawer/pull/186)
- Keep the filter visible when an active query's live listing falls below the threshold. [PR #183](https://github.com/L-K-M/TopDrawer/pull/183)
- Index standardized targets once during a bulk drop. A Debug fixture with 250 existing file bookmarks and 50 new ones measured 344 ms before the change and 8 ms after for the store operation. [PR #187](https://github.com/L-K-M/TopDrawer/pull/187)
- Preserve UTF-8 names and paths through Linux mountinfo escape decoding (SOL-05). [PR #182](https://github.com/L-K-M/TopDrawer/pull/182)
- The earlier drawer interaction review covers keyboard selection after Backspace and clipboard excerpts that show matching text. [Keyboard selection PR](https://github.com/L-K-M/TopDrawer/pull/184) [clipboard excerpt PR](https://github.com/L-K-M/TopDrawer/pull/185)
- An earlier review tracks silent launcher-save failures in separate implementation work.

Independent implementations also cover the filter and linked-folder regressions in BACKLOG U1. Choose one implementation per behavior. [Active filter](https://github.com/L-K-M/TopDrawer/pull/181), [folder availability](https://github.com/L-K-M/TopDrawer/pull/190).

Two additional PRs preserve byte-distinct clipboard text across restarts and keep compact drawer headers visible. A hosted macOS rendering with one column and 32-point icons reproduced an 88-point folder drawer that clipped the title, gear and empty-state text. The 220-point treatment showed all three. [Clipboard text identity](https://github.com/L-K-M/TopDrawer/pull/189), [compact drawer headers](https://github.com/L-K-M/TopDrawer/pull/188).

A later drawer-and-clipboard pass opened independent implementations of the byte-distinct clipboard identity ([#191](https://github.com/L-K-M/TopDrawer/pull/191), alongside #189) and the match excerpt ([#195](https://github.com/L-K-M/TopDrawer/pull/195), alongside #185), plus two small fixes: keep shared Pict icons ahead of fetched favicons ([#193](https://github.com/L-K-M/TopDrawer/pull/193)) and preview the first result on Space ([#205](https://github.com/L-K-M/TopDrawer/pull/205)). Choose one implementation per behavior.

A reliability pass opened four more implementations: a batch of small correctness fixes — update-timer re-entry, a stale Carbon hotkey press, case-folded recents identity, standardized Spotlight hit paths, `*.app` file classification, and conservative unknown-Trash counts ([#192](https://github.com/L-K-M/TopDrawer/pull/192)); asynchronous Settings item icons ([#194](https://github.com/L-K-M/TopDrawer/pull/194)); per-edge stack renumbering on a Settings move ([#196](https://github.com/L-K-M/TopDrawer/pull/196)); and a “Locate Tab” pill outline ([#206](https://github.com/L-K-M/TopDrawer/pull/206)).

A further pass opened focused fixes: folder popovers opening inward from the drawer's own edge ([#211](https://github.com/L-K-M/TopDrawer/pull/211), merged) and a dangling-symlink collision check in `FileMover` ([#216](https://github.com/L-K-M/TopDrawer/pull/216), merged). Its update-download timeout ([#207](https://github.com/L-K-M/TopDrawer/pull/207)), prerelease pagination ([#208](https://github.com/L-K-M/TopDrawer/pull/208)) and hotkey-recorder hint ([#217](https://github.com/L-K-M/TopDrawer/pull/217)) were closed as superseded when [#220](https://github.com/L-K-M/TopDrawer/pull/220) adopted the shared Livery, Keycap and Updraft packages; the underlying findings now belong to those packages.

The Opus 5.5 pass opened twelve PRs. Each has a regression test where one was practical. The ones that change visible behavior were checked on this Mac. If one closes without landing, its line below is the finding:

- Folder, Disks, Network and Cloud drawers opened at the empty size, then snapped larger once the listing landed after the open animation. A drawer now reopens with its tab's last listing (up to 32 remembered; when full, the oldest is dropped) and revalidates in the background. The first open of a tab still sizes late. [#198](https://github.com/L-K-M/TopDrawer/pull/198)
- Type-to-find was dead below five items. That includes the first-run Apps tab, whose Welcome note asks the user to "just start typing". A printable key now opens the filter field, and Delete edits a query whose field lost focus. [#199](https://github.com/L-K-M/TopDrawer/pull/199)
- Rename, Change Icon and Empty Trash activated Top Drawer for their dialog and never handed focus back. A click in the folder pop-up or a preview also left the app active after the drawer closed. `ModalActivation` returns activation to the previous app, but only while Top Drawer still holds it. [#200](https://github.com/L-K-M/TopDrawer/pull/200)
- A subfolder clicked in the Browse Folder pop-up opened Finder and closed the drawer. The pop-up now walks into subfolders with a Back button, and Back shows the enclosing listing at once. [#201](https://github.com/L-K-M/TopDrawer/pull/201)
- Pointing at a drawer item changed nothing. Grid cells, list rows, search results and pop-up rows now show a subtle hover plate, cleared when a drag disables the cell. [#202](https://github.com/L-K-M/TopDrawer/pull/202)
- Tab colors came from a bare color well. A row of fixed swatches (the dark-mode system hues of macOS 11 to 15) now sits beside a Custom well in New Tab, the tab editor, the icon editor and the default-color preference. [#203](https://github.com/L-K-M/TopDrawer/pull/203)
- The pill's tooltip never appeared: the non-activating tab panel lacked `allowsToolTipsWhenApplicationIsInactive`. The tooltip now also names the tab's live hotkey ("Apps (⌃⌥A)"), and Move to Edge marks the current edge. [#204](https://github.com/L-K-M/TopDrawer/pull/204)
- Settings "+" ignored the New tab grid defaults. [#213](https://github.com/L-K-M/TopDrawer/pull/213)
- List and search rows drew no drop ring over a Trash item, though dropping there trashes the file. [#214](https://github.com/L-K-M/TopDrawer/pull/214)
- VoiceOver announced neither a missing target nor the title actually shown. The label is now the shown title, and the value starts with "Missing". [#215](https://github.com/L-K-M/TopDrawer/pull/215)
- One wrong-typed scalar field in a tab (for example a numeric title) dropped the whole tab with its items and note text, and the next autosave persisted the loss. [#218](https://github.com/L-K-M/TopDrawer/pull/218)
- One unreadable clipboard entry hid the whole history and stopped saving until Clear. Entries now decode one by one, and an archive with no readable entry is left untouched. [#219](https://github.com/L-K-M/TopDrawer/pull/219)

Findings these PRs left open are filed under the sections below.

## Resolved on main

These findings are resolved on main, so the sections below no longer list them. Most were resolved by [#220](https://github.com/L-K-M/TopDrawer/pull/220), which adopted the shared Keycap, Updraft and Livery packages:

- The doubled daily update timer: Updraft's `start()` invalidates the previous timer.
- App-reserved ⌘ shortcuts: Keycap refuses ⌘Q, ⌘W, ⌘H, ⌘M, ⌘Space, ⌘Tab and the ⇧⌘ screenshot keys, and the Tabs pane flags an older saved combo it no longer registers.
- The recorder kept consuming keys after losing focus (SOL-24): Keycap's `ShortcutRecorder` records only as first responder, and focus loss stops recording.
- "Check for Updates…" during a running check, and Download during a running download, did nothing. Updraft queues and reports the check, and the second Download opens the release page.
- Punctuation keys rendered as "key 0x2B": Keycap names keys from the current keyboard layout.
- Rejected hotkey combos were consumed silently: Keycap's recorder beeps and keeps recording. The superseded [#217](https://github.com/L-K-M/TopDrawer/pull/217) also showed an inline reason ("needs ⌘/⌃/⌥ or a function key"); if that is still wanted, it belongs in Keycap or a wrapper in `HotkeyRecorderView`.
- A move could target a dangling symlink: merged in [#216](https://github.com/L-K-M/TopDrawer/pull/216), where any symlink occupies the name via `destinationOfSymbolicLink`, with tests for a dangling link and a loop.

## Reliability and data safety

### Duplicate layout identities make entries ambiguous (SOL-02)

bugs — important

`MacDring/Store/TabStore.swift:133-145,302-316` accepts duplicate identities. `MacDring/Tabs/TabController.swift:237-240` gives two tabs sharing a UUID one window. Duplicate item UUIDs within a tab make edits and drop targets select an ambiguous entry, including children in groups. This affects imported or hand-edited layouts.

Reject duplicate tab IDs and per-tab item/container IDs before accepting a document. Failed import must retain the existing layout; invalid on-disk originals must survive recovery. The same item UUID in different tabs can remain valid because operations include tab identity. Add import and recovery regressions. Effort: about half a day.

### Partial launcher recovery can become permanent data loss (SOL-03)

bugs — important

`MacDring/Model/LauncherDocument.swift:24-25` and `MacDring/Model/Tab.swift:133-135` drop unreadable records. `MacDring/Store/TabStore.swift:141-145,799-801` accepts a partially recovered document; successive autosaves eventually replace both primary and backup with that reduced document. Reproduce with one valid tab and one invalid anchor, then mutate and save twice.

Retain a recovery original whenever decoding loses records and expose that recovery before accepting destructive rewrites. Preserve working tabs while making omissions visible. Effort: one day.

### Group-name drafts disappear on uncommitted exits (SOL-07)

bugs — important

`MacDring/Drawer/DrawerView.swift:107-108,306-339` commits only through Return or Back. Switching tabs or closing the drawer without either discards the draft, although the group header promises commit when leaving. `MacDring/Drawer/DrawerWindowController.swift:226` resets group context on open.

Commit the draft against its originating group on focus/session exit, with lock and stale-session checks. Verify tab switching, click-outside, and Return on macOS. Effort: half a day.

### Filing, Undo, and eject failures lack actionable feedback (SOL-09)

general issues — important

`MacDring/Tabs/TabController.swift:917,921,1381-1383,1444,1470-1477` ignores or logs several operation results. Partial moves show a success-only count for the subset moved; failed Undo, eject, and open-with drops leave users unsure what happened or where their files went.

Return per-operation results, retain retryable failures, and show an accessible error alongside any completed subset. Extend the existing ordinary-launch error banner rather than adding another reporting mechanism. Effort: one to two days.

### Pending login approval is represented as unknown or enabled (SOL-10)

general issues — important

`MacDring/Model/LoginItemManaging.swift:24-41` omits approval-pending state. `MacDring/Model/Preferences.swift:238-239,303-308` can retain an enabled toggle although launch at login will not happen. Disabling does not unregister a pending registration.

Represent approval-pending explicitly, offer Open Login Items, and unregister pending registrations when disabled. Verify the real ServiceManagement approval flow. Effort: half a day plus macOS verification.

### Web-editor remnants mislead and ship dead code (SOL-11)

general issues — nice-to-have

`MacDring/Notes/NotesEditorWebView.swift` and `NotesEditorSchemeHandler.swift` are no longer referenced since the notes editor moved to `NotesEditorNativeView`, yet remain compiled; the EditorWeb docs also still describe the web editor as a shipping integration. Dead paths still compile and are still reviewed.

Delete the unreferenced app-target files and correct the docs; keep `EditorWeb/` and the pure `NotesEditorBridge`/`HostSession` (still tested). Effort: small.

If the web path is kept instead, fix its delivery bookkeeping: `NotesEditorHostSession.nextMessage()` commits `deliveredDocumentID`, `deliveredMarkdown`, `deliveredTheme` and `revision` before returning (`NotesEditorHostSession.swift:131-157`), while `NotesEditorWebView.evaluate` fires `evaluateJavaScript` without a completion (`NotesEditorWebView.swift:178-183`). A page-side exception leaves the session believing the document arrived, with no retry. Commit delivered state from the completion handler, or revert it on failure. The native editor is unaffected.

### A cleared note can never reconcile in the host session

bugs — nice-to-have

`MacDring/Notes/NotesEditorHostSession.swift:139`: once `desiredDocumentID` becomes `nil` the session returns `nil` forever and `isInSync` stays false while a delivered document lingers.

Add an explicit clear-document path or tolerate the nil-then-sent state. Effort: small-medium.

### Stopping the daemon leaves signal emission live

bugs — nice-to-have

`linux/Sources/TopDrawerDaemon/TopDrawerService.swift:167-176`: `stop()` leaves `self.connection` set, so `emitSignal` keeps writing signals on a stopped service.

Nil the connection in `stop()`. Effort: trivial.

### Recents change detection keys on mtime alone

bugs — nice-to-have

`linux/Sources/TopDrawerDaemon/TopDrawerService.swift:479-484`: `checkForRecentsFileChange` compares only mtime, so a rewrite preserving mtime (`touch -r`, some sync tools) silently drops a `RecentsChanged` signal.

Also compare size or inode. Effort: trivial.

### A same-named file counts as the watched directory appearing

bugs — nice-to-have

`MacDring/Common/INotifyWatcher.swift:186`: in parent-watch mode a plain file created with the watched directory's name sets `directoryAppeared`, causing a spurious change and re-arm.

Verify `directoryExists` or the `IN_ISDIR` bit before treating it as appeared. Effort: small.

### Repeated watch failures stack concurrent retries

bugs — nice-to-have

`MacDring/Common/INotifyWatcher.swift:162`: every failed `armWatch` enqueues another unconditional retry, so repeated failures can run multiple retry timers at once.

Add a `retryPending` flag so at most one retry is outstanding. Effort: small.

### The failed-favicon set grows without bound

general issues — nice-to-have

`MacDring/Common/FaviconCache.swift:28` pins every definitive-miss host in `failed` for the whole session; unlike `images` (capped at 128) it never shrinks — a small leak in a long-lived agent.

Bound or periodically clear `failed`. Effort: small.

The same set also pins transient failures. `FaviconCache.download` returns `.definitiveMiss` for any non-200 status or undecodable image (`FaviconCache.swift:91-92`), `record` adds the host to `failed` (:127-128), and `fetch` short-circuits on it (:56). A passing 502, 429 or 408 therefore hides the favicon for the rest of the session, although `Outcome.transportError` (:80) is the retryable path. Map 5xx, 408, 429 and unexpected statuses to `.transportError`; pin only 400, 403, 404, 410 and an undecodable 200. Effort: 30 minutes.

### A hotkey press can fire once after unregister

general issues — nice-to-have

`MacDring/Hotkeys/CarbonHotkey.swift:59`: `DispatchQueue.main.async { me.onPressed?() }` captures `me` strongly, so a queued press fires after `unregister()` — a stale hotkey acts on a dead registration.

Capture weakly or check `hotKeyRef != nil` inside the block. Effort: trivial. Implemented in [#192](https://github.com/L-K-M/TopDrawer/pull/192), which captures the exact `EventHotKeyRef` and compares it on the main queue so a re-register on the same instance cannot let a queued press through. PR #220 then deleted the app's `CarbonHotkey.swift` in favor of Keycap, whose `CarbonHotkey` still dispatches `DispatchQueue.main.async { [self] in onPressed?() }` with no registration check, so the fix now belongs in Keycap.

### A transient bus restart permanently kills the daemon

general issues — nice-to-have

`linux/Sources/TopDrawerDaemon/Daemon.swift:223-235`: a failure inside `withSessionBus`'s closure and a failure to connect share the same `exit(1)`, so a transient bus restart kills the daemon instead of reconnecting.

Distinguish connect failure (retry with backoff) from service failure, or document a required systemd `Restart=`. Effort: small. Partly stale: `linux/systemd/topdrawerd.service:29-30` already ships `Restart=on-failure` and `RestartSec=2`, so the daemon comes back unless systemd's start limit trips after repeated failures. `Daemon.run` still exits on any bus or service failure with no in-process reconnect.

### The shell never retries a failed bus connection

general issues — nice-to-have

`linux/Sources/topdrawer-shell/main.swift:153-168`: if `DBusClient.withSessionBus` fails (no session bus at login), the task logs once and never retries — content updates stay dead until restart.

Retry the whole connect-and-observe block on a timer. Effort: small.

### TabStore carries a Swift 6 data-race diagnostic

general issues — nice-to-have

`MacDring/Store/TabStore.swift:227` warns "reference to captured var `self` in concurrently executing code" even in Swift 5 mode — a latent race if the project moves to Swift 6.

Restructure the capture or mark the boundary explicitly. Effort: small.

### A plain file named like an app is treated as an application

bugs — nice-to-have

`MacDring/Model/DrawerItem.swift:218-224` classifies any path ending in `.app` as `.application` without checking it is a bundle directory, so a plain file named `notes.app` is routed through app-launch paths and fails instead of opening as a file.

Require `isDirectory` for `.application` and fall through to the file classification otherwise. Effort: ten minutes plus a test. Implemented in [#192](https://github.com/L-K-M/TopDrawer/pull/192).

### Quarantine failure leaves a corrupt store in place

bugs — nice-to-have

`MacDring/Store/TabStore.swift:95-107` only logs when moving a corrupt `launcher.json` aside fails (destination name taken in the same second, read-only directory). The corrupt file stays at the primary path and `saveNow` then rotates those bytes over the `.bak`, straining the preserved-copy contract the comment above it promises.

Make `quarantine` report success and, on failure, skip the normal save rotation (or write to a fresh destination name). Effort: one hour.

### Launcher decode parses the document twice

general issues — nice-to-have

`MacDring/Store/TabStore.swift:133-141` runs `JSONSerialization.jsonObject` over the same bytes `JSONDecoder` just parsed, only to count a `tabs` array — double parse cost and peak memory at launch on large documents.

Derive the raw-tab count from the lenient decode itself, or drop the sentinel check. Effort: one hour.

### Deduplicate Fresh files that have multiple path spellings

bug hypothesis — reproduce with a real Spotlight hit before changing identity

`SpotlightQuery` constructs URLs from indexed paths, and `FreshLister.merge` already deduplicates standardized file URLs. A symlink or alternate mount spelling may still leave two rows for one file. Reproduce using a temporary landing zone and a symlink in direct scan and Spotlight together. Decide whether aliases should remain separate launch targets. If they should converge, compare resource identities in the listing phase with a path fallback. Avoid extra synchronous probes on the main actor; keep ordinary different paths distinct. Addressed in [#192](https://github.com/L-K-M/TopDrawer/pull/192): Spotlight hits are standardized at construction, while the display-name fallback keeps the reported (unstandardized) path so resolving a symlink cannot rename the row.

### Recents may retain multiple spellings of a local file

bug hypothesis — validate on case-sensitive and case-insensitive volumes

`RecentsStore` deduplicates by URL equality. Case variants may be aliases of one file on one volume and distinct files on another. Use a verified local file identity or a volume-aware path comparison once there is a reproducible alias. Keep case-sensitive paths and web URLs distinct, and retain the newest entry. Addressed in [#192](https://github.com/L-K-M/TopDrawer/pull/192): file targets fold to a lowercased standardized path, web URLs stay exact, and the newest entry is retained.

### Treat unsupported Trash entry counts as unknown

bug — verify on a filesystem without ATTR_DIR_ENTRYCOUNT

`TrashInspector.isEmpty` falls back to directory link count, which cannot detect loose files. This can display the empty icon and disable Empty Trash even when files are present. Model the unsupported result conservatively and keep Empty Trash available when emptiness cannot be established. Preserve the metadata-only path so opening a menu never triggers a Trash access prompt. Add a test for an unsupported attribute with a low link count. Implemented in [#192](https://github.com/L-K-M/TopDrawer/pull/192): an unavailable entry count is treated as non-empty, so Empty Trash stays available, and the metadata-only path is unchanged.

The opposite case is separate: a missing `~/.Trash` also reports as full. `TrashInspector.swift:35-41` always includes the home Trash. When the directory is absent, `entryCount` (:70-84) hits ENOENT and `attributesOfItem` (:63) returns nil, so `isEmpty` returns false (:65). The Trash item then shows full and "Empty Trash…" stays enabled with a count of 0. When both metadata reads fail, check `fileExists(atPath:)` and treat an absent directory as empty. Effort: trivial.

### Scan the intended prerelease history

bug — relevant when prerelease checking is enabled

`GitHubReleaseClient` picks the highest version from the first 30 releases. When publication order differs from version order, a higher-version prerelease can sit on an older page. Define the supported history window or follow pagination with a bounded request policy and a test for out-of-order version tags. The app-local client was removed by [#220](https://github.com/L-K-M/TopDrawer/pull/220); Updraft's `GitHubReleaseClient` still requests one `releases?per_page=30` page, so the fix now belongs in Updraft. The superseded [#208](https://github.com/L-K-M/TopDrawer/pull/208) followed 100-entry pages to a 10-page budget, stopped on a short page, and picked the maximum non-draft version. A later-page failure should keep the pages already fetched, and the request budget should respect GitHub's 60/hour unauthenticated limit.

### Keep per-path icon overrides from attaching to unrelated files

general issue — respect transient listing limits

`TabStore` retains the path-keyed overrides for live rows. A repointed folder can keep irrelevant styles indefinitely; a later file that reuses a path can pick up an old style. Clear or explicitly migrate revision-specific styles on folder replacement. Investigate durable file identity before pruning on refresh: caps, hidden-file filters and a temporarily unavailable volume can all hide a still-valid item. Test a rename, path reuse, folder replacement, and partial listings.

### Separate durable tab identity from immediate availability

**Bug and usability.** AppDelegate's menu suggests it opens tabs even when parked on a disconnected display. `TabController.openDrawer` requires a resolved screen and a live pill. An enabled row then performs no visible action. Build menu rows from the same placement state the controller uses. For parked tabs, show their state and route to placement settings, or offer a separately designed temporary opening that leaves the saved anchor intact. Verify disconnect and reconnect, an already-open drawer, and the move-to-main setting. This complements the backlog's portable import display mapping.

The per-tab hotkey has the same gap. `reconcile` calls `registerHotkeyIfNeeded(for:)` outside the placement switch, so a parked tab keeps its Carbon hotkey (`TabController.swift:253-255`), while `toggle(tabID:)` goes through `openDrawer`, which returns early for a parked tab (:455-470). The key is swallowed and nothing happens. Either unregister hotkeys for parked tabs (freeing the combination) or route the press to the same parked-tab explanation as the menu.

### A fetched favicon can override the shared store's link icon

reliability / icon precedence — nice-to-have

`ItemView.resolveIcon` returns the shared Pict icon for a `.url` item (precedence rung 3), but the resolution `.task` then replaces it with a fetched favicon whenever the item has no image or generated-style override. The favicon is the kind-specific default (rung 5), so a link with a shared icon set is demoted to its site favicon. Gate the fetch on the shared lookup, and reuse that lookup rather than resolving the target twice. In review: [PR #193](https://github.com/L-K-M/TopDrawer/pull/193). Effort: small.

### Unknown SF Symbol names blank the tab pill

visual / forward compatibility — nice-to-have

`TabStripView.glyphView` draws `Image(systemName: name)` with no fallback. A document written by a newer build (or hand-edited) can carry a symbol this OS does not know, leaving an empty glyph on an otherwise colored pill. `IconName` only maps names for Linux; macOS renders the stored name unchanged. Fall back to `TabGlyph.default` when the symbol cannot be resolved, and cover it at the name-resolution layer. Effort: small.

### A store or display change mid-drag teleports the dragged pill

bugs — important

`reconcile()` has no `draggingTabID` guard. It calls `wc.update(tab:)`, which resets `model.edge` and the anchor, and `wc.place(on:)` for every placed tab (`MacDring/Tabs/TabController.swift:239-248`). `place` recomputes `restingFrame` from the stored anchor and applies it at once (`TabWindowController.swift:243-269,312-355`). `deOverlapStackedTabs()` filters only on `isShown`, `currentScreen` and the store (`TabController.swift:301-307`) and reads `previewSnap`'s frame as `restingFrame` (`TabWindowController.swift:423-428`), so it can call `setRestingFrame` and persist the preview position (`TabController.swift:332-337`). Any store, display or preference change during a drag triggers this. Related to BACKLOG R1 and R9 but distinct.

Skip the dragged tab in `deOverlapStackedTabs`, make `place(on:)` a no-op while a drag previews, and commit the anchor only in `endDrag`. Effort: small.

### One malformed icon style discards every generated icon in the tab

bugs — nice-to-have

`Tab.init(from:)` decodes `iconStyles` with `decodeLenient([String: IconStyle].self, …)` (`MacDring/Model/Tab.swift:158`). Dictionary decoding is all-or-nothing, so one wrong-typed entry turns the whole map into `[:]`, `DrawerItem.applyingIconStyles` (`DrawerItem.swift:166-174`) applies nothing, and the next save persists the loss. Decode entries one by one, as `FailableDrawerItem` does for items (`Tab.swift:133`), and keep the good ones. Pairs with #218. Effort: one hour plus a test.

### Atomic saves replace a symlinked store or history file

bugs — nice-to-have

`TabStore` keeps the store URL verbatim (`MacDring/Store/TabStore.swift:61`) and writes with `.atomic` (:799); `ClipboardHistoryStore` does the same (:29, :113). An atomic write renames a temporary file over the destination, so a symlinked `launcher.json` (for example one kept in a synced folder) becomes a regular file on the first save, and the link target stops updating. Resolve the URL once at init (`resolvingSymlinksInPath()`) and write to the target. Effort: one hour.

### Persisted hex colors decode without validation

bugs — nice-to-have

`Tab.colorHex` (`MacDring/Model/Tab.swift:130`) and `IconStyle.colorHex` (`IconStyle.swift:43`) accept any string. Render paths then degrade silently: Livery's `Color(hexString:)` falls back to `.clear` (an invisible pill fill and Settings dot), and `IconRenderer` to `.systemBlue`. `Preferences` validates the default color only at launch (`Preferences.swift:220`); its `didSet` stores any string (:93-95). Validate at decode with the same check as `Preferences.validColor`, and in the `didSet`. Effort: 30 minutes.

### Fresh badge scans can overwrite each other

bugs — nice-to-have

`refreshFreshBadges` captures `now` once (`MacDring/Tabs/TabController.swift:1579`). With direct scan off, the `else` branch sets `freshBadgeScannedRecent = false` (:1592), but an in-flight background scan's `main.async` completion can overwrite it (:1581-1590), and overlapping scans have no generation guard. The Spotlight completion reuses the stale `now` (:1597), so an arrival that aged out meanwhile still counts. Superseded Spotlight queries cannot deliver, because `start` cancels the previous one (`SpotlightQuery.swift:34-35,61-66`). Stamp each pass with a generation, re-check `preferences.freshDirectScan` in the completion, and take `Date()` there. Effort: small.

### A folder entry with unreadable resource values sorts as a file

bug hypothesis — needs a filesystem repro

`FolderLister.swift:79-86` reads `values?.isDirectory ?? false`, so an entry whose resource values are missing sorts among the files (:65). The row itself is rebuilt by `DrawerItem.transientFileItem`, which stats again (:54), so the visible effect is wrong folders-first ordering unless the second stat also fails. On a missing value, re-check with `fileExists(atPath:isDirectory:)` and skip the entry if that fails too. Effort: one hour.

### Disk, Cloud and Trash items dim while their target is briefly absent

bugs — nice-to-have

`ItemView` computes `broken` from `BookmarkResolver.isBroken(item)` (`MacDring/Drawer/ItemView.swift:223-224`) and dims to 45% (:113). `isBroken` exempts only `.url` and `.group` (`BookmarkResolver.swift:62-66`), so a volume or cloud provider that drops out between listings, or a Trash item, renders dimmed with "Can't find", although `resolveIcon` already gives `.disk`, `.cloud` and `.trash` their own glyphs (:514-528). With #215, VoiceOver would also call them "Missing". Actions are unaffected: Quick Look, Browse Folder and Open With apply only to files and folders. Exempt kinds that have a defined fallback, so only broken file, app and folder launchers dim. Effort: one hour.

### A launched tool's descendants can hang the Linux daemon

bugs — important

`LinuxProcess.run` calls `readDataToEndOfFile()` (`linux/Sources/TopDrawerDaemon/LinuxProcess.swift:43`) before `waitUntilExit()` (:44), and its watchdog (:40-41) signals only the direct child. A tool that backgrounds a child inheriting stdout or stderr keeps the pipe open, so the read never sees EOF and the watchdog cannot end it. Handlers run inline on the actor-isolated `DBusObjectServer` (dbus 0.4.1 `DBusClient.swift:117`), so the whole service stops answering. Redirect child output to `/dev/null` or a file, or wait first with a bounded read and escalate to SIGKILL. Reordering wait-before-read alone brings back the pipe-buffer deadlock for noisy tools. Effort: small.

### A removable root filesystem is offered for ejection on Linux

bugs — important

`classifyOne` excludes only `systemPrefixes`, which do not include `/` (`linux/Sources/TopDrawerDaemon/LinuxVolumes.swift:112`), and returns `.disk, ejectable: true` for any `/dev/*` device whose `/sys/block/<base>/removable` is 1 (:170-172). A system booted from a USB stick therefore lists `/` as ejectable, and `Eject` checks only that flag (`TopDrawerService.swift:226-229`) before running `udisksctl unmount` and `power-off` on the running system disk (`LinuxVolumes.swift:288-289`). The macOS `DisksLister` skips the startup volume. Reject `/` and the device backing it in `classifyOne`. Effort: small.

### Linux eject may report success when the unmount failed

bug hypothesis — needs a device

`VolumeEjector.eject` discards the unmount result and returns true whenever `udisksctl power-off` exits 0 (`linux/Sources/TopDrawerDaemon/LinuxVolumes.swift:288-289`), with no mount-table check. udisks normally refuses to power off a drive with a mounted filesystem, so the harmful case needs a device to confirm; the discarded result also covers the benign already-unmounted race. Before returning true, confirm the mount point is gone from `/proc/self/mountinfo`, treating already-unmounted as success. Effort: small.

### An unknown recents source empties a Linux Recents tab

bugs — nice-to-have

`servesSystemRecents` and `servesMacDringRecents` match only `system`/`both` and `macDring`/`both` (`linux/Sources/TopDrawerDaemon/LinuxRecents.swift:181-193`), so an unknown or empty value matches neither and `recentsHits` returns `[]` (`TopDrawerService.swift:563-565`). macOS decodes the field leniently with the fallback `.macDring` (`MacDring/Model/Tab.swift:157`), so a document from a newer build shows history on macOS and nothing on Linux. Mirror the fallback in `TabInfo`. Effort: trivial.

### The Linux daemon serves a missing, unreadable or corrupt document alike

general issues — nice-to-have

`LauncherDocumentSource.rawJSON` maps any read failure to `"{}"` (`linux/Sources/TopDrawerDaemon/LauncherDocumentSource.swift:43-45`), `GetDocument` serves it verbatim (`TopDrawerService.swift:197-201`), and the shell shows its "no tabs" placeholder (`linux/Sources/topdrawer-shell/main.swift:150`). A corrupt store looks like a fresh install. Expose a load status, or a distinct error from `GetDocument`. Adjacent to BACKLOG A4. Effort: small.

## Performance and responsiveness

### Settings resolves file icons inside its render path (SOL-14)

performance problems, stuttering, and jank — important

`MacDring/Settings/TabsView.swift:304-307` calls icon resolution during each body evaluation. `MacDring/Drawer/ItemView.swift:213-228,495-574` shows that this work resolves bookmarks and reads icons from disk. Large launchers, stale bookmarks, or remote targets can beachball Settings repeatedly.

Resolve row icons asynchronously, keyed by the item, with a placeholder and cancellation. Reuse the drawer's resolution approach. Profile opening and changing settings for a 100-entry tab. Effort: half a day. Implemented in [#194](https://github.com/L-K-M/TopDrawer/pull/194): an `AsyncItemIcon` reuses `ItemView.resolveIcon` off the render path with a cancellation handler.

Not covered by #194: the folder tab editor resolves its folder bookmark in `body` (`TabsView.swift:533`), on the main thread on every re-render, including each keystroke in the Name field. Resolve once per selected tab.

### Per-tab thickness re-measures text every layout pass

performance problems, stuttering, and jank — nice-to-have

`MacDring/Common/DrawerAppearance+SwiftUI.swift:28` runs an NSString text measurement for every tab on every layout pass — small but repeated hot-path work.

Cache the measured line height keyed on (title, font, weight). Effort: small.

### Every DocumentChanged signal triggers a full refetch

performance problems, stuttering, and jank — nice-to-have

`linux/Sources/TopDrawerShell/DaemonClient.swift:383-397`: each `DocumentChanged` fires an immediate `fetchTabs` with no debounce, so a burst of saves means one `GetDocument` round-trip per signal.

Coalesce fetches (skip if one ran within ~200ms or is in flight). Effort: small.

### Bound the cost of rapid folder refreshes

DrawerWindowController.apply starts a new read for each relevant reconcile. BackgroundListing drops obsolete replies after the disk call completes. A burst can leave several full directory reads running even when only the newest result can be used. Instrument queued, active and delivered reads against a delayed loader. Prototype one active and one replaceable pending refresh per target. Opening a different local drawer must stay responsive while an earlier network read is blocked. Verify newest settings win after a sort change and dismissing cannot revive a panel.

### Measure and coalesce full-text clipboard searches

A release-optimized Foundation microbenchmark on this Mac took a median 47 ms across 11 scans for an absent word in 50 distinct near-256 KiB ASCII clips. It exercised the same locale-aware, case- and diacritic-insensitive range search as DrawerModel. This is a synthetic worst-case workload and excludes SwiftUI. Profile query changes, selection changes and unrelated view updates with ordinary clips and the upper-bound fixture. Cache results by query and history revision, then consider moving scans off the main thread if typing still misses frames. Verify original ordering, history removal during a search, and stale result rejection.

### Clipboard archive I/O blocks the app thread

performance — measure before redesigning

`ClipboardHistoryStore` synchronously loads the archive during controller construction, then encodes and atomically writes it on the main queue after captures and privacy-sensitive actions. The current limits permit a raw text payload of about 12.5 MiB and a JSON read cap of roughly 75 MiB.

Profile first open, steady capture, and quit with a full archive. Move read and encode/write onto a serialized worker if the measurements warrant it, or lower the realistic payload cap. Preserve entry ordering, private permissions, quit flush, and archive removal when retention is disabled or the last Clipboard tab is deleted. Test an in-flight save followed by Clear or deletion.

### Stop compositing blur beneath opaque surfaces

**Performance hypothesis.** The drawer always creates a behind-window visual effect view, even with the fully opaque Solid backing; the modern pill likewise creates blur behind Flat and High Contrast. Profile multiple visible pills with Core Animation or Instruments, including window movement behind the launcher. If measurable, build blur only for treatments where it contributes to the rendered result. Compare screenshots under Light, Dark and Reduce Transparency, and compare compositor work for 1, 12 and 30 visible tabs.

### Retain last good contents when a watched remote folder becomes unavailable

**Performance and UX follow-up.** Start with explicit read errors. Evaluate whether a same-target refresh failure should retain a marked, read-only snapshot for slow or temporarily disconnected shares. Keep the timestamp and a Retry action, and do not accept a file drop against a stale URL. Changing the target must immediately remove old rows and state. Mock a successful read followed by failure, target replacement and recovery. Profile network stalls before adding a retry timer. Coordinate any retry behavior with the existing refresh coalescing proposal.

### Make a long live listing feel bounded while it is opening

**Performance hypothesis.** The 300-item cap in `FolderLister` is applied after enumerating, fetching sort properties and sorting all entries. `DrawerView.searchResultsList` constructs an eager stack of matches and each row reports external-drop geometry. Benchmark local and remote folders at 300, 10,000 and 50,000 entries, and a broad query across a large items drawer. Consider bounded top-K selection with the exact existing sort order, and a lazy result stack whose hit-testing still works after scrolling. Report p50/p95 latency to first results and result-scroll hitch rate. Count icon requests for a one-letter query, repeat with rapid edits, arrow to the final result and drop onto a row revealed by scrolling. Keep query ranking separate from row creation in the measurements.

### Launcher document I/O runs on the main thread

performance — nice-to-have

`AppDelegate.swift:8` builds `TabStore()` eagerly, so `launcher.json` is read synchronously at launch (`MacDring/Store/TabStore.swift:68`). Every `mutate` (:761-767) schedules a full re-encode and atomic write on the main queue (:769-802), and `setNotes` (:647-652) goes through `mutate`, so typing in a note rewrites the whole document every 0.3 s. Load before the UI needs the document, and encode and write on a serial background queue from a snapshot with a generation gate; keep `saveNow()` synchronous for quit and tests. Measure with a large document first. Distinct from "Launcher decode parses the document twice". Effort: half a day.

### Spotlight hits are checked on disk on the main thread

performance — nice-to-have

`SpotlightQuery` delivers on the main queue (`MacDring/Store/SpotlightQuery.swift:45-49`). Recents maps each hit through `RecentItem(spotlight:)` (`TabController.swift:1692-1694`, `RecentsLister.swift:38-41`), and Fresh merges through `FreshLister.items` (`TabController.swift:1701-1702`, `FreshLister.swift:22-31`). Both reach `DrawerItem.kindAndName(for:)`, a `fileExists` plus a `displayName` per hit (`DrawerItem.swift:214-234`): up to 30 for Recents and 40 for Fresh. Recents also discards the name Spotlight already supplied (`SpotlightQuery.swift:87`). The opt-in Fresh direct scan already runs off the main thread. Build the items off the main thread and apply them if the watch key is still current. Effort: one to two hours.

### Display UUIDs are recomputed on every reconcile

performance — nice-to-have

`DisplayRegistry.uuidString(for:)` runs `CGDisplayCreateUUIDFromDisplayID` and `CFUUIDCreateString` on every call (`MacDring/Screens/DisplayRegistry.swift:29-40,55-59`), and `screen(for:)` derives a UUID for each `NSScreen` in turn. `reconcile` calls it per tab (`TabController.swift:243`) and again per de-overlap member (:326-327), and `resolvedScreen` (:530-537) and `cycleTab` (:425-431) add more, on every debounced store or preference change. Memoize by `CGDirectDisplayID` and clear the cache on `didChangeScreenParametersNotification`. Profile with 30 tabs first. Effort: small.

### The notes editor runs two whole-note wiki transforms per keystroke

performance — nice-to-have

The `NSText.didChangeNotification` observer calls `accept(storageText(in: editor))` (`MacDring/Notes/NotesEditorNativeView.swift:157-163`), and the engine binding's setter evaluates `storageText(in:)` again (:101-112). Each call runs `WikiLinkService.makeDisplayState` and `makeStorageState` over the whole note (:173-180), and the engine syncs wiki links in its own `textDidChange` as well. Compute the storage text once per keystroke and share it, or skip the transform when the note has no wiki links. Measure typing latency in a long note first. Effort: small to medium.

### The Linux daemon's bus loop runs blocking work inline

performance — important

`DBusObjectServer` is an actor, and `Connection.run` awaits each handler inline (dbus 0.4.1 `DBusClient.swift:117`, `DBusObjectServer.swift:198`), so handlers run strictly one at a time. `Eject` shells out up to three times (`linux/Sources/TopDrawerDaemon/LinuxVolumes.swift:288-292`, up to 20 s), `Launch` waits on `LinuxProcess.succeeds` with a 15 s default (`TopDrawerService.swift:259-280`, `LinuxLauncher.swift:104`), and `GetRecents` for a Fresh tab scans a directory with a `statx` per entry (`TopDrawerService.swift:553-566`, `FreshScanner.swift:46-56`). `Ping`, `GetDocument` and the shell's `fetchTabs` wait behind all of it. Move subprocesses and scans to a separate actor or queue and reply asynchronously. Effort: medium.

### The Linux running-apps poll reads every cgroup every two seconds

performance — nice-to-have

The watch ticks every 2 s (`linux/Sources/TopDrawerDaemon/TopDrawerService.swift:120`) and calls `ProcRunningApps.runningAppIDs()` (:367), which lists `/proc` and reads every `<pid>/cgroup` (`LinuxRunningApps.swift:80-99`); `GetRunningAppIDs` scans again (:408). Poll less often or on demand, or cache the pid list and read only new pids. Effort: small.

## Interface and workflow

### Portable imports have no display mapping (SOL-16)

missing features — important

`MacDring/Settings/TabsView.swift:108-124` imports foreign display UUIDs unchanged. Under the default policy, `MacDring/Screens/TabPlacementPolicy.swift:31-35` parks every tab whose display is unknown. Users moving layouts between Macs can get an apparently empty launcher, and the enabled status-menu rows cannot open the parked drawers.

Map unknown imported displays to a chosen connected display. Keep same-machine restoration separate from portable import. Verify an export from another display UUID set. Effort: one day.

### Deleting a notes tab has no recovery step (SOL-17)

missing features — important

`MacDring/Settings/TabsView.swift:151-154`, `MacDring/Tabs/TabStripView.swift:59-61`, and `MacDring/Store/TabStore.swift:168-174` remove an unlocked tab immediately. One Remove Tab action destroys all its note text, without confirmation or document Undo.

Confirm deletion of nonempty notes/populated tabs or offer document-level Undo. Preserve the lock rules and verify both deletion surfaces. Effort: half a day for confirmation, longer for shared Undo.

### Primary tab surfaces lack explicit accessible activation (SOL-23)

usability: speed, convenience, and clarity — important

`MacDring/Tabs/TabStripView.swift:33-63` provides gestures and a tooltip without explicit accessible button activation, title, or open state. With labels hidden, VoiceOver users lack a reliable way to identify and toggle a tab. `MacDring/Drawer/ItemView.swift:124-126` also omits running/broken state. Exact announcements remain unverified on Linux.

Expose one labeled accessible element per control, button activation, open/selected state, and meaningful item status. Verify with VoiceOver and Accessibility Inspector. Effort: one day including assistive-technology checks.

### Folder and Trash drops advertise Copy while removing the source (SOL-25)

usability: speed, convenience, and clarity — important

`MacDring/Drawer/DrawerWindowController.swift:66-77` always returns the Copy drag operation. `MacDring/Tabs/TabController.swift:920-942` can instead move files or trash them. The plus-badge cursor misleads users during file operations.

Derive drag operation from target and source mask. Distinguish add-reference, open-with, move/copy, and Trash, with supported modifier behavior. Verify Finder and cross-volume drops. Effort: one day plus device checks.

### Broken launchers have no Relink action (SOL-18)

missing features — nice-to-have

`MacDring/Drawer/ItemView.swift:113-192` dims missing targets but provides no Relink action. When both bookmark and fallback fail, users must delete and re-add the item, losing placement, name, and customization.

Offer a file picker that replaces only the target/bookmark after validating its kind, through the existing store/service boundary. Effort: half a day.

### Keyboard navigation does not expose item actions (SOL-19)

missing features — nice-to-have

`MacDring/Tabs/TabController.swift:1814-1847` handles arrows, Return, and Space, but the actions in `MacDring/Drawer/ItemView.swift:127-192` remain mouse-oriented. Keyboard-only users cannot invoke Rename, Lock, Reveal, Open With, or Eject through the current selection.

Add a selected-item actions shortcut and accessible named actions. Effort: one day plus assistive-technology checks.

### Clipboard history captures plain text only

missing features — nice-to-have

`ClipboardMonitor.captureChanges` reads only `.string`; images, files, and rich text are invisible. Users coming from Paste or Maccy expect image and file entries.

Record a bounded set of types (thumbnail images, file URLs as items) behind the existing opt-in. Effort: medium-large.

### Clipboard entries cannot be pinned

missing features — nice-to-have

A frequently-needed snippet ages out after 50 copies with no way to keep it.

Add pin/favorite entries that survive clearing. Effort: medium.

### Drawer items cannot be dragged out

missing features — nice-to-have

Items in an `.items` drawer can be reordered or grouped but never dragged out to Finder, another app, or the Trash item — DragThing users expect drag-out-to-move.

Add `.onDrag` to item cells alongside the reorder gesture (in-drawer reorders, drag-out exports the URL). Effort: medium.

### No way to search across all tabs

missing features — nice-to-have

Type-to-find only searches the open drawer; there is no global search across tabs.

A global filter (hotkey or dedicated Search tab) aggregating every tab's items. Effort: medium-large.

### No keyboard path to remove a selected item

usability: speed, convenience, and clarity — nice-to-have

`MacDring/Tabs/TabController.swift:1811+`: Delete/Backspace does nothing to the selected item; removal is context-menu-only, so keyboard users can't remove without a mouse.

⌘⌫ (or ⌫ with no query) removes the selected item when editable and unlocked. Effort: small.

### A desktop id outside scan dirs fails to launch

usability: speed, convenience, and clarity — nice-to-have

`linux/Sources/TopDrawerDaemon/LinuxLauncher.swift:237-245`: an `application` item whose bare `foo.desktop` id misses the scan dirs falls through to `gio launch` on a relative path and never tries `gtk-launch`, unlike `openWith`.

Add a `gtk-launch <id>` fallback. Effort: small.

### Restoring settings can trigger a spurious folder prompt

usability: speed, convenience, and clarity — nice-to-have

`MacDring/Settings/GeneralView.swift:82`: `.onChange(of: preferences.freshDirectScan)` fires folder-access prompts for any value change, including programmatic restore/import, not just the user's toggle.

Trigger the prompt from the Toggle's action binding instead. Effort: small.

### Reordering in Settings renumbers every tab globally

usability: speed, convenience, and clarity — nice-to-have

`MacDring/Settings/TabsView.swift:159`: `moveTabs` rewrites `anchor.order` for every tab globally, so unrelated edges get renumbered on each move — needless persisted churn.

Only renumber what changed. Effort: small. Implemented in [#196](https://github.com/L-K-M/TopDrawer/pull/196): `TabPlacementPolicy.reorderedTabs` renumbers only the moved tabs' own display+edge groups and leaves other edges' persisted order untouched.

### Gate filtered results on the search field being shown

`DrawerModel.displayedItems` switches on `isSearching` alone, while `isSearchable` also decides whether the field is rendered. Today `DrawerWindowController.show` clears the query on every open and `.notes` renders its own pane, so the mismatch is unreachable — but a defensive `isSearching && isSearchable`, or a test pinning the invariant, costs nothing. Effort: trivial.

### Web launches land in Linux recents as empty rows

usability: speed, convenience, and clarity — nice-to-have

`linux/Sources/TopDrawerDaemon/RecentsRecorder.swift` + `LinuxRecents.swift` (`RecentEntry.init`): `Launch` records non-file kinds into recents and emits `url.path`, which is empty for `https://` hits — useless empty-path rows.

Skip non-file kinds or emit the full URL. Effort: small.

The same `url.path` loses a folder's trailing slash (`LinuxRecents.swift:20`), and `RecentFileHit` carries no kind (`MacDring/Store/RecentFilesQuery.swift:15-21`), so a launched folder is re-emitted looking like a file. Emitting the full URL, or adding a kind field, fixes both.

### New-tab actions fail silently without a display

usability: speed, convenience, and clarity — nice-to-have

`MacDring/Settings/NewTabWindowController.swift:44-46` and `MacDring/Settings/TabsView.swift:133-139` silently return when `registry.mainScreenUUID()` is nil, so the "+" button or dialog does nothing with no explanation.

Surface a short explanatory alert instead of a silent no-op. Effort: one hour.

### The header truncation badge is a dead end

usability — capped Folder listings

`DrawerView.header` shows a count such as 300+ when `FolderLister` has more entries than its cap. The tooltip explains the cap, and the existing Finder action can reach every file. Give the cap an accessible label and clearly connect it to the Finder action. Test both exactly 300 results and a capped folder on a narrow drawer.

Fresh and Recents never show the badge at all. `FreshLister` keeps the newest 40 hits without saying it dropped any (`FreshLister.swift:18,24`), and their results arrive through `applySpotlightResult` and `updateLiveItems` (`TabController.swift:1733-1742`, `DrawerWindowController.swift:308-314`), which never set `model.itemsTruncated`; only `gatherListing` does, for Folder, Disks, Network and Cloud (:323-332). Report whether the cap cut the list and set `itemsTruncated` for `.fresh` and `.recents`. Effort: one to two hours.

### Test interrupted closes as well as opens

DrawerWindowController.show guards its animation completion with presentationGeneration. The animated hide checks isVisible alone. Exercise close A, reopen B, close B before A finishes. Record whether A's completion can remove B's panel early, clear its rows or reset opacity during the second fade. If reproducible, bind close cleanup to its originating generation. Check zero-duration switches, the riding pill and Reduce Motion.

### Paste into a drawer to create launchers

usability — keyboard workflow

Settings already offers an Add Link sheet. Direct paste into an Items drawer could add a URL or file reference without leaving the drawer. Define how plain non-URL text should be handled before expanding support beyond file URLs and links. Fetch clipboard contents only on the deliberate action. Respect editable text focus, item locks, and the existing drop deduplication policy. Verify that a paste into notes or the filter still edits the focused field.

### Offer update download progress, cancellation, and completion feedback

usability — make the transfer state visible

`UpdateChecker.downloadAndReveal` tracks a Boolean, then reveals the download in Finder or opens the release page on failure. The user has no explicit progress or cancel action and receives little feedback while waiting. Give the transfer a visible state with completion and failure details. Test a slow server, cancellation before and during transfer, temporary file cleanup, and the browser fallback. The app-local checker and downloader were removed by [#220](https://github.com/L-K-M/TopDrawer/pull/220). Updraft's downloader already carries a 30 s request and 15 min resource timeout (the superseded [#207](https://github.com/L-K-M/TopDrawer/pull/207) proposed 60 s and 15 min), and a failed download shows an alert offering the release page. Progress, cancellation and a retry-oriented message for `URLError.timedOut` are still missing and belong in Updraft.

### Offer Quick Look when selection starts in an unfiltered drawer

usability — keyboard navigation

Return can use the first visible item before the user moves the selection. Space currently requires a selected item. A reasonable shortcut could preview the first previewable item in an unfiltered drawer, or select it before invoking Quick Look. Treat Space as text while the filter is being edited so users can enter multiword queries. Verify grid, list, Clipboard, and Notes key paths.

### Give new tab types a single chooser with examples

**Missing affordance and usability.** `AppDelegate.buildMenu` lists nine creation actions, while the plus button in `TabsView` creates an Items tab immediately. Introduce a single New Tab chooser (with keyboard selection) available in both places. Describe what each tab watches and show a sample row or note; keep Folder selection and Clipboard consent in the deliberate creation flow. Keep a fast path for creating an Items tab. Validate time to create a Folder tab and to discover Fresh without documentation. The chooser can host optional starter kits later.

### Add a placement map to Settings

**Missing feature and usability.** Display and edge pickers plus the position slider edit numeric placement without showing nearby tabs, the reserved Dock/menu areas or parked tabs. Preview the selected display's edges at scale with named marker positions. Read the same layout and overlap policy used by the windows. Start with a noninteractive preview and a spoken position label; add drag editing only if manual trials show a need. Test two displays of different size and orientation and a saved disconnected anchor.

### The drawer header count ignores the active filter

usability — trivial

`DrawerView.header` always shows `items.count` (or the clipboard entry count) even while a filter is active, so the number disagrees with the rows on screen. Show "matches of total" while searching, and keep the untruncated total for the tooltip.

The count is also an unlabeled number. It sits next to the lock (`DrawerView.swift:216-223`; the "2" in `screenshot.png`), its tooltip is empty unless the listing was truncated, and on an Items tab it restates what is visible and reads like a badge. Show it for live listings only, where it is information, as "12 items" with matching accessibility text, and keep the "300+" case. A search-time variant: "N matches" in the search bar plus a one-line key hint (↑↓ select, Return open, Space preview, Esc close) that hides after the first arrow key. Effort: one hour each.

### Remember a drawer's scroll position per tab

missing feature — nice-to-have

A folder or list drawer with more rows than fit reopens at the top. Store the last scroll offset (or first visible item id) per tab and restore it on reopen, clearing it when the listing changes length or the tab is repointed. Verify a capped folder, a search result list and a notes drawer.

A smaller case within one session: leaving a group lands at the top of the grid. `.id(model.openGroupID)` on the `ScrollViewReader` (`DrawerView.swift:298-308`) rebuilds the scroll view to get the crossfade, so Back from a group starts at offset 0. Keep the ScrollView's identity and crossfade only the content, or `proxy.scrollTo(groupID)` after closing the group. Effort: two hours.

### Releasing a reorder outside the grid moves the item anyway

usability — nice-to-have

`targetSlot(at:)` falls back to the nearest slot with no distance limit (`MacDring/Drawer/DrawerView.swift:549-553`), so releasing a dragged item over the header, the filter field or below the last row reorders it instead of cancelling. External drops already limit snapping to the cells' union inset by 24 pt (`DrawerHostingView`). Return `nil` outside that union and treat it as cancel. Effort: one hour.

### Type-to-find cannot find a group by name

missing features — nice-to-have

`DrawerModel.searchResults` filters `items.flattenedLaunchable()` (`MacDring/Drawer/DrawerModel.swift:141`, `DrawerItem.swift:179-181`), which drops the groups themselves, so typing a group's name finds nothing. Include groups whose name matches; Return already opens a group result. Pairs with "Explain where a matching launcher lives". Effort: one hour with tests.

### Input methods lose the first type-to-find keystroke

usability — needs a device check

With #199, a drawer without a visible filter field takes the first keystroke in its key monitor, before any text input client exists. With a CJK input method the first character lands as a plain Latin letter, and composition starts only with the second. When the current keyboard input source is not ASCII-capable, show and focus the field without inserting the key, so that the next keystroke starts composition. Check with Japanese and Pinyin input.

### Escape does not reach the folder pop-up after a row click

usability — partly reproduced

`FolderBrowserController.show` uses a `.semitransient` popover with no Escape path (`MacDring/Drawer/FolderBrowserController.swift:19`), and the drawer's key monitor returns at `guard event.window === drawer.window` (`TabController.swift:1806`) before its Escape case (:1829-1835). On this Mac, with #201 applied, Esc closed the pop-up after a click on its header. After a row click opened a subfolder, though, neither Esc nor a trial ⌘[ Back shortcut reached the pop-up, while accessibility reported the drawer panel as the focused window. Find out which window is key after a row click and whether the monitor sees those events, then add a local Escape monitor in `show` (and a Back shortcut). Effort: small once diagnosed.

### The folder pop-up lacks Open With and the tab's appearance

usability — nice-to-have

`FolderBrowserView` builds `ItemView` with only `onLaunch`, `onReveal` and `onPreview` (`MacDring/Drawer/FolderBrowserView.swift:30-33`), and `ItemView` offers Open With only when `onOpenWith` is set (`ItemView.swift:135-136`); neither `browseFolder` path passes it (`DrawerWindowController.swift:200-215`, `TabController.swift:1204-1214`). It also omits `appearance:`, so the pop-up uses default fonts and titles and, with #202, the standard hover strength even under High Contrast. Pass the drawer's `onOpenWith` and `DrawerModel.appearance` through `FolderBrowserController`. Effort: small.

### The web preview has no Stop button

usability — nice-to-have

`showWebPage` loads with the default 60 s timeout (`MacDring/Drawer/ItemPreviewController.swift:335`). The toolbar has only Open and Close, `stopLoading()` runs only at teardown (:128), and a slow or trickling host spins with no way to abort short of closing. Add a Stop button while loading, and consider a 30 s `timeoutInterval`. Effort: small.

### Clipboard rows give no feedback, and Clear has no confirmation

usability — nice-to-have

A row click only calls `onCopyClipboardEntry` (`MacDring/Drawer/ClipboardHistoryView.swift:43`). It never sets `model.selectedItemID`, which drives the highlight (:58), and `copyClipboardEntry` closes the drawer unless "keep open" is on (`TabController.swift:1180-1188`). With keep-open, a click shows nothing and the highlight stays on the previous row. Select the clicked row and swap its glyph for a checkmark for about 600 ms. The header trash wipes the whole history at once (`DrawerView.swift:245-247`); confirm first, and reuse the confirmation for Clear Recents. Effort: small.

### Recents entries can only be cleared all at once

missing features — nice-to-have

`RecentsStore` exposes only `record` and `clear` (`MacDring/Store/RecentsStore.swift:33-41`). `editable` is true only for Items tabs (`DrawerView.swift:59`), so Recents rows get no Remove (:584), and the header trash clears everything (`TabController.swift:1167-1171`). Clipboard rows already have per-entry removal. Add `RecentsStore.remove(id:)` and a Remove action for entries Top Drawer recorded, with the existing undo toast. BACKLOG A8 covers undo for Clear Recents, not this. Effort: half a day.

### Dialog text fields may not take focus when the dialog opens

usability — check on device

The New Tab name field (`MacDring/Settings/NewTabView.swift:40`), Add Link (`TabsView.swift:579`) and the symbol picker's search (`SymbolPickerView.swift:31`) have no `@FocusState`, so typing right after a dialog opens may go nowhere. Check which ones AppKit already focuses, and add `.focused` with an `.onAppear` focus where it does not. Effort: one hour.

### Customize Icon hides and replaces a custom image

usability — nice-to-have

For an item with a custom image, Customize Icon previews the default generated folder (`MacDring/Tabs/TabController.swift:1407-1410`, `IconEditorView.swift:29-45`), and saving replaces the image. Preview the current image, or say that saving replaces it. Effort: small.

### Status menu polish

usability — small each

Tab rows never show which drawer is open (`MacDring/AppDelegate.swift:208-224` sets no `state`); mark it with `.on`. Each row could also show its tab's hotkey right-aligned, and a Keyboard Shortcuts… item could open a small cheat sheet. Toggling Launch at Login from the menu silently reverts on an `SMAppService` failure (`AppDelegate.swift:263-266`); show the error that Settings → General already displays. SOL-10's pending-approval state is separate.

### Focus may stay with Top Drawer after Settings or the icon editor closes

usability — check on device

#200 hands activation back after the three modal prompts, and after a drawer close that left the app active with no window. A drawer close caused by opening Settings or the icon editor leaves activation alone, since those windows take the keyboard, and nothing hands it back when they close. If Top Drawer stays active with no window, the next keystrokes go nowhere. Close Settings, read `NSApp.isActive` and the frontmost app, and if confirmed, call `ModalActivation.handBackIfIdle` from their close handlers with the app recorded when they opened.

### Launch several items without the drawer closing

missing features — nice-to-have

A launch closes the drawer unless the tab's "keep open after launch" is on (`MacDring/Tabs/TabController.swift:1300`), so launching three apps means reopening the drawer twice. ⌘-click already reveals (`ItemView.swift:117`). Make ⌥-click and ⌥-Return launch and keep the drawer open for that one launch, carrying the intent on the launch request rather than changing the tab's behavior. Effort: half a day.

### Pill menu quick actions

usability — medium

The pill menu offers Configure, Move to Edge and Remove (`MacDring/Tabs/TabStripView.swift:51-62`); Lock Position and opening the drawer live only in the open drawer's header, and #204 left them out. Add Open Drawer, Add Files…, Add Link…, Lock Position, New Tab…, Duplicate Tab and a Color submenu (reusing #203's `TabPalette`), wired through new `TabStripModel` callbacks to the existing `TabController` and `TabStore` paths.

### Dragging a locked pill gives no feedback

usability — nice-to-have

`previewDrag` and `endDrag` return early for a locked tab (`MacDring/Tabs/TabController.swift:761-777,804-808`) without any cue; the only lock signal is the disabled Remove item (`TabStripView.swift:59-61`). The pill feels stuck for the whole gesture. Play one `.levelChange` haptic or show `NSCursor.operationNotAllowed` when the drag starts. Effort: small.

### Live Recents and Fresh items cannot be opened over D-Bus

missing features — needed before LP-21 and LP-22

`Launch(itemID)` resolves against the document (`linux/Sources/TopDrawerDaemon/TopDrawerService.swift:259-280`, `LauncherItems.swift:27-45`), `OpenWith` needs a desktop-file id (:281-288), and Recents and Fresh hits are transient, so no call opens one. macOS launches them through `onLaunch`. The LP-20 shell renders only tab titles, so nothing breaks yet. Add `OpenURI(s uri)` or a path form of `Launch`, recording into recents. Effort: small to medium.

### Installed applications cannot be listed over D-Bus

missing features — nice-to-have

No method enumerates applications (`linux/Sources/TopDrawerDaemon/TopDrawerService.swift:180-320`, `linux/README.md:46-58`); `DesktopEntryScanner.scan` (`DesktopEntry.swift:171-190`) is used only by tests. An LP-22 frontend cannot build an app grid or an Open With picker. Add `GetApplications() -> s` returning the scan as JSON. Effort: small.

## Visual design and accessibility

### A maximum-size drawer can push its pill off-screen (SOL-20)

visual issues and layout problems — important

`MacDring/Drawer/DrawerMetrics.swift:135-136` allows an items drawer to consume screen depth minus 16 points. The riding pill is at least 24 points thick, and `MacDring/Screens/EdgeLayout.swift:160-180` adds it and a 22-point animation nudge outside that allowance. Unlike notes at `DrawerWindowController.swift:510-517`, large items drawers can strand the close target or spill onto an adjacent display.

Bound one combined drawer/pill/animation envelope for every edge. Add pure containment cases for small visible frames, then check real display behavior. Effort: half a day plus macOS verification.

### Metadata columns use configured rather than visible width (SOL-21)

visual issues and layout problems — nice-to-have

`MacDring/Drawer/ItemView.swift:107-109,362-368` chooses fixed metadata columns from nominal column/icon settings. `MacDring/Drawer/DrawerMetrics.swift:135` can clamp the actual panel much narrower. On narrow displays, Size/Kind can squeeze names or overflow available width.

Choose metadata columns from measured available row width after clamping. Verify large-icon list layout on a narrow screen. Effort: half a day.

### Translucent pill contrast is chosen from the tint alone (SOL-26)

aesthetics and theming — nice-to-have

`Color.readableForeground` (`MacDring/Model/Color+ReadableForeground.swift` since PR #220; formerly `ColorHex.swift:62-65`) chooses foreground from tint luminance, while `MacDring/Tabs/TabStripView.swift:96-111` renders idle fill at 62% opacity. A middle-dark tint selects white text, but bright underlying content can reduce contrast. This is a source-derived visual risk, not a measured current-screen contrast failure.

Use a sufficiently opaque label backing or a tested composited palette. Check light, dark, and busy wallpapers. Effort: half a day.

### Appearance choices lack a live contextual preview (SOL-27)

aesthetics and theming — nice-to-have

`MacDring/Settings/TabAppearanceEditor.swift:7-32` offers presets, hidden labels, and typography without a representative preview. Users must repeatedly open a drawer to judge those choices.

Add a small tab-and-items preview using the existing view styles, bound to the same settings values. Effort: one day.

The New Tab dialog and the tab editor have the same gap for one tab. Show a small `TabStripView` bound to the draft name, color, glyph and style, and add an Open Drawer button to the editor.

### Derive the popover edge from the positioning view

visual issues and layout problems — nice-to-have

`FolderBrowserController.preferredPopoverEdge(for:isFlippedView:)` takes a Bool the call site must keep in sync with the view passed to `NSPopover.show`. Add an `of positioningView: NSView` overload so the edge hint and the positioning rect always come from the same coordinate system. Effort: trivial.

### Disconnected displays are indistinguishable in the picker

visual issues and layout problems — nice-to-have

`MacDring/Settings/TabsView.swift:512` labels every missing display "Disconnected display"; with several, the user can't tell them apart.

Include a UUID suffix or last-known name in the fallback label. Effort: trivial.

Connected displays have the same problem: the picker labels screens by `localizedName` only (`TabsView.swift:504-512`), so two identical monitors look the same. Add an index or position suffix ("LG UltraFine, left").

### Fresh-item sparkle replays on every reopen

visual issues and layout problems — nice-to-have

`MacDring/Drawer/DrawerWindowController.swift:306-307`: `sparklingItemIDs` persists until the next apply and the animation runs once per `onAppear`, so a freshly landed item re-sparkles each reopen within its five-minute window.

Clear sparkling ids after the animation completes. Effort: small.

### Tabs cannot follow the system accent color

aesthetics and theming — nice-to-have

`MacDring/Model/Preferences.swift` fixes the default tab color at `#0A84FF` with no "follow system accent" option, so tabs can't match the Mac's accent.

An "Accent" color choice resolving `NSColor.controlAccentColor`. Effort: small.

A related product call: every new tab starts as the same default, so a fresh setup is a column of identical pills. New Tab could pick the first swatch from #203's palette that no tab uses yet, but that changes what the "Default tab color" preference means, so #203 left it out. Decide whether the preference is a fixed default or a starting point for a rotation.

### The group preview tile is invisible on light backings

aesthetics and theming — nice-to-have

`MacDring/Drawer/ItemView.swift:339` tints the iOS-style group tile fixed `.white.opacity(0.16)`; over the light appearance's solid/frosted backing it's subtle-to-invisible.

Derive the tint from `Color.primary` or the tab color. Effort: small.

### The appearance preview misrepresents the thickness slider

visual issues and layout problems — nice-to-have

`MacDring/Settings/AppearanceView.swift:115-152` renders the preview tab at `max(18, tabThickness * 0.52 * scale)`, so it floors at 18 pt and can never show the thinnest setting; the undocumented factor makes the slider look weaker than it is.

Render the preview at the configured thickness under one documented preview scale. Effort: one hour.

### Recency sections go stale while a drawer stays open

visual issues and layout problems — nice-to-have

`MacDring/Drawer/DrawerView.swift:356-365` computes the Today/Yesterday/This Week/Older sections with the wall clock of each render, so a drawer left open across midnight keeps items under stale headings.

Re-evaluate the buckets on a coarse timer, or document open/refresh-only behavior. Effort: one hour.

While there, make the section headers sticky (pinned in the `LazyVStack`) so the time context does not scroll away in a long Recents or Fresh list.

### Generated icons drop their glyph on unknown symbol names

aesthetics and theming — nice-to-have

`MacDring/Common/IconRenderer.swift:55-63` silently skips drawing when `iconStyle.symbol` fails to resolve (corrupted document, or an SF Symbol retired by an OS update), leaving user-styled icons as bare tiles.

Fall back to the kind's default glyph (or a neutral placeholder) when the symbol lookup fails. Effort: one hour.

A valid glyph can vanish too. `IconRenderer.drawFolder` embosses the symbol in fixed `.white` (`IconRenderer.swift:35`), while `drawTile` uses `contrastingColor(on: fill)` (:47, helper :74-77). A generated icon with the Folder base and a pale color draws a white glyph on a light folder. Use `contrastingColor(on: fill)` in both. Effort: trivial.

### The drawer's tab tint is flat

aesthetics and theming — nice-to-have

`MacDring/Drawer/DrawerView.swift:100-110` paints the tab color as a uniform 10% wash, so many open drawers read alike and tab identity lives mostly in the pill.

Deepen the tint toward the drawer's inner edge (a subtle gradient from the tab color), checking text contrast in the high-contrast preset. Effort: two to three hours.

### Verify the spoken controls for choosing a tab glyph

SymbolPickerView shows its selected glyph with an accent fill. Its symbol buttons and the icon-only add/remove/import/export buttons in TabsView rely on images and help text. Inspect their actual accessible names and selection traits with VoiceOver, including the same picker in IconEditorView. Supply explicit action names where synthesized names fail, expose the selected glyph in speech and shape, and verify the disabled removal hint for a protected tab. Do this alongside the existing pill activation work, which covers different controls.

At the 180-point sidebar minimum, compare the four borderless footer buttons with a labeled layout menu beside add and remove. Test whether a first-time user can distinguish import (which replaces the layout) from export, including by keyboard. Check the emoji palette and remove-symbol action for meaningful names.

### Make reduced motion coherent across drawer interactions

**Visual design and accessibility.** Opening and closing, tab movement, selection scrolling, undo banners, and Fresh sparkles use several animation paths. Introduce one policy for spatial movement and decorative motion that honors the system Reduce Motion setting and the app's speed control. Preserve immediate target highlights and selection visibility. Compare stock settings and Reduce Motion across all four edges, preview opening, tab cycling and a drop. Measure time to first actionable frame, rather than just animation duration. Apply this policy before considering extra hover lift or arrival pulses.

### Make the first row of decisions consistent

**Interface and visual design.** The supplied screenshot shows the pill and header both naming the drawer, then a tiny standalone count, a lock, and a gear. Current `DrawerView.header` still clusters the same elements, with up to two additional icon actions. Keep a stable gear and one primary kind action in recognizable positions, reserve truncation for long names, and group lower-frequency controls where they remain discoverable via mouse and keyboard. Keep the duplicated title only where it helps identify icon-only or long-name tabs. Mock the narrowest drawer with a long title, a clipboard drawer, the issue/error state and VoiceOver labels before changing the header.

One way to free the header: an overflow menu holding Sort by, Show Hidden Files, Grid/List and Refresh for folder-like tabs, which today live only in Settings, plus a path breadcrumb under the title (`DrawerView.header`, :208-253).

### Add a current visual acceptance set

**Aesthetics and maintenance.** The README screenshot still shows MacDring branding and the earlier notes presentation. Replace it after checking the native app. Capture: a compact vertical Items tab, a horizontal Notes drawer with native formatting, and a list on a light background. Use clean sample names and content, and capture the real open state and the location of the tab relative to the drawer. Also keep a sign-off checklist for Dark/Light, color extremes, long text, 1×/2× displays and small panels. The visual target is one legible rim and a restrained material treatment, with a clear selected item and sufficient contrast for the small header controls.

### Use the tab color as the drawer's interaction color

aesthetics — nice-to-have

Grid/list selection, focus and progress use the system accent, while the tab color is only a 10% wash. Tinting selection with the tab's own color would strengthen per-tab identity on a screen with several drawers. Keep the system accent in Settings, and check the high-contrast preset and the existing selection contrast.

### Render monogram tabs on a small tile

delight — small

A letters/emoji glyph is currently bare text in the readable foreground. Drawing it on a tiny rounded tile in the tab color would make monogram tabs look intentional and match the pill's continuous corners. Keep the monogram to the two characters the pill already renders.

### Give the modern pill a subtle inner highlight

aesthetics — small

A 1 pt top-left light stroke or a soft gradient would make the translucent pill read as a physical object rather than a flat bar. Combine with the existing hover-lift and reduced-motion work, and compare Light/Dark plus Reduce Transparency.

### Notes resize handles are 6 points wide and mouse-only

accessibility — important

`DrawerMetrics.notesResizeInset` is 6 (`MacDring/Drawer/DrawerMetrics.swift:18`), and `NotesDrawerResizeView.layout` uses it as the edge handle width (`NotesDrawerResizeView.swift:39-50`); corners are 16 pt (:16). `HandleView` draws a faint glyph at 45% alpha (:119) and has no accessibility role, value or keyboard path, while `handleDrawerKey` returns early on arrows in a notes drawer (`TabController.swift:1843-1855`). Make the hit area larger than the drawn strip (about 14 to 20 pt, corners about 24 pt) and expose each handle as an adjustable accessibility element. Effort: small to medium.

### Clipboard rows announce up to 160 characters as their name

accessibility — nice-to-have

Each row's label is `"Copy \(entry.preview)"` (`MacDring/Drawer/ClipboardHistoryView.swift:61`), and `preview` is up to 160 characters (`ClipboardEntry.swift:9-13`), so VoiceOver reads a long log line as the control's name. Use a short label ("Clipboard entry, 240 characters, copied 2 minutes ago"), move the preview to `accessibilityValue`, and add a hint that activating copies. See also "Make clipboard results legible at narrow drawer widths". Effort: trivial.

### Clipboard timestamps tick every second

visual issues and layout problems — nice-to-have

`Text(entry.date, style: .relative)` (`MacDring/Drawer/ClipboardHistoryView.swift:50`) renders "1 min, 12 sec" without "ago" and re-renders every row each second while the drawer is open. Use a named relative date ("2 min ago") refreshed by a minute-level `TimelineView`, or `RelativeDateTimeFormatter`. Effort: one hour.

### Switching drawers snaps the outgoing pill home

visual issues and layout problems — nice-to-have

`openDrawer` closes the previous tab with `setOpen(false)` and `restoreResting()` (`MacDring/Tabs/TabController.swift:475-477`), an instant `setFrame` (`TabWindowController.swift:273-280`), while `closeDrawer` animates the same return (`TabController.swift:511-513`). Switching drawers by hotkey or hover snaps the outgoing pill in one frame while every other pill movement animates. Use `wc.animate(to: wc.restingFrame, duration: animationDuration)` there too. Effort: trivial.

### A store change snaps a hover-revealed tab shut

visual issues and layout problems — nice-to-have

`reconcile` calls `refreshConcealment(animated: false)` (`MacDring/Tabs/TabController.swift:269`). For a hover-revealed tab with the pointer outside its zone, `SpringLoadPolicy.revealTransition(reveal: false, isConcealed: false, animated: false)` returns `.concealNow` (`SpringLoadPolicy.swift:80-84`), and `applyRevealState` cancels the pending re-conceal and conceals at once (`TabController.swift:666-679`), skipping the 0.45 s `reConcealDelay` the live monitor grants. Tell launch-time snaps apart from steady-state reconciles. Effort: small.

### Concealed tabs hide the Fresh arrival dot

visual issues and layout problems — needs a device check

The arrival dot is an overlay inside the pill's content (`MacDring/Tabs/TabStripView.swift:77-85,159-164`). A `.hide` tab slides off-screen (`TabWindowController.swift:328-337`), and the shared-edge sliver shows only the clean edge strip (:361-369), so the dot cannot be seen; `.fade` leaves it at 20% opacity (`Preferences.swift:36`). Concealment is opt-in. Draw the dot independently of the pill content, or fade rather than hide while a Fresh tab has a pending arrival. Effort: medium.

### The drawer slides toward the edge while its tab slides away

aesthetics and theming — prototype

`show` starts the panel 22 pt inside its open frame and moves it outward (`MacDring/Drawer/DrawerWindowController.swift:239-246`, `EdgeLayout.nudgedDrawerFrame`), while the pill moves inward from the screen edge to the drawer's inner face (`TabController.swift:494-497`). The two motions run in opposite directions, so the drawer reads as dropping in rather than being pulled out by its handle. The inward start exists so a slide never spills onto an adjacent display. Try keeping the window at its final frame and animating a mask that uncovers the drawer from the screen edge in step with the pill (same duration and curve), with the window shadow off until it settles. Tune on device, including Reduce Motion (instant) and the notes resize gutter. Effort: one to two days.

### Drawer tooltips over another app's full-screen window

visual issues and layout problems — unverified

#204 found that AppKit shows tooltips only in the active app or the key window unless the window sets `allowsToolTipsWhenApplicationIsInactive`. Drawers show tooltips because the drawer panel becomes key (`MacDring/Drawer/DrawerWindowController.swift:278`), except over another app's full-screen window, where `ForeignFullScreen.covers` keeps it non-key. Setting the same flag on the drawer panel likely fixes that case; check over a full-screen app before changing it.

### Favicons are capped at 64 pixels

visual issues and layout problems — nice-to-have

`FaviconCache.maxPixelSize` is 64 (`MacDring/Common/FaviconCache.swift:35`, used at :106), but icons render at up to 128 pt (`Preferences.swift:214`, `ItemView.swift:398`). On a Retina display the default 64 pt icon is upscaled 2×, and the largest 4×. Derive the cap from twice the largest icon size (256 px). Effort: trivial.

### Swapping items may flash a placeholder icon

visual issues and layout problems — check on device

`.id(item.id)` on every grid cell and list row (`MacDring/Drawer/DrawerView.swift:611`, list :401) resets the cell's icon cache when a swap moves another item into the slot, which may show the 1×1 placeholder until the icon task finishes. Check on device before changing it.

### The Linux strip ignores vertical edges and has no width bound

visual issues and layout problems — nice-to-have

The strip's box is always horizontal (`linux/Sources/topdrawer-shell/main.swift:111`), while only the layer-shell anchors and margins follow `--edge` (:76-83), so `--edge left` anchors a horizontal row of titles to the left edge. `renderTabs` joins every title with no cap (:148-151), the label never ellipsizes (:120), and `gtk_layer_set_size` is never called, so dozens of tabs overflow the monitor. Orient the box by edge, cap the surface to the monitor, and ellipsize or show "+N more". Effort: small.

## Feature prototypes

### Undo for removed launcher entries

`TabController` removes an item from its drawer immediately. Extend the existing file-move Undo toast to restore a removed launcher's identity, customization, original group and slot. Show the item's name. Exercise a newly occupied slot, group dissolution, locked entries and switching drawers during the Undo window. Estimated effort is two to three hours.

### Locate a tab from its Settings row

`TabsView` identifies rows by color, title and edge. Two same-name tabs on the
same edge of different displays can look identical. Try a **Locate Tab** action
that outlines the corresponding pill while Settings retains focus. Keep the
drawer, saved anchor and pill size stable. Use a static outline with Reduce
Motion. Give parked tabs a display name or a stable disconnected-display label.

Evaluate recognition with duplicate names, hidden labels, light and dark
backgrounds, and two displays. For dozens of tabs, test filtering rows by title,
kind, edge and display. Preserve selection by tab ID. Disable reordering while
filtered unless the move maps unambiguously to the full list. Verify that
VoiceOver distinguishes the rows. Implemented in [#206](https://github.com/L-K-M/TopDrawer/pull/206): a Locate Tab button outlines the pill with a static ring (no drawer, focus or anchor change) and disables itself for parked tabs.

Still open for long lists: a filter field above the list, an item count per row, and a row context menu (Open Drawer, Add Files…, Duplicate, Export Tab…, Remove).

### Explain the pending drop before releasing it (SOL-28)

novel, delightful, or quirky ideas worth trying — nice-to-have

`MacDring/Drawer/DrawerWindowController.swift:66-77` and `MacDring/Drawer/DrawerView.swift:397-436` show a target ring without explaining the pending action. New users must remember whether a tile opens, files, trashes, or adds a launcher.

After a brief dwell, show target-specific text such as “Move to Downloads” or “Open with Preview,” using the same operation policy as the cursor. Test whether it reduces hesitation without obscuring the target. Effort: half a day after SOL-25.

### Offer non-destructive starter drawer kits (SOL-29)

novel, delightful, or quirky ideas worth trying — nice-to-have

`MacDring/AppDelegate.swift:274-328` supplies Apps/Welcome. Useful Folder/Fresh/Notes combinations still require manual discovery; the import flow at `MacDring/Settings/TabsView.swift:108-124` replaces the entire layout.

Offer a few optional local kits, such as “Downloads desk” with Folder, Fresh, and Notes, added without replacing current tabs and removable in one action. Reuse existing tab types; no automation or permissions are needed. Effort: one to two days.

### Badge counts on the tab pill

novel, delightful, or quirky ideas worth trying — nice-to-have

Per-tab counts on the pill itself — Fresh shows "3" for newly landed files, a watched folder shows pending items — glanceable without opening.

A badge overlay driven by the live listing counts. Effort: medium.

### Shell-command items

novel, delightful, or quirky ideas worth trying — nice-to-have

A drawer item that runs a small script and copies the result — clipboard-friendly workflows without leaving the drawer.

New item kind with a bounded subprocess runner. Effort: medium-large.

### An edge-glow pulse on listing changes

novel, delightful, or quirky ideas worth trying — nice-to-have

A subtle edge-glow pulse on the pill when a watched folder or Fresh listing gains items — ambient notification without a badge.

A brief pill highlight driven by the existing watch callbacks. Effort: small.

### Drag one tab onto another to merge drawers

novel, delightful, or quirky ideas worth trying — nice-to-have

`MacDring/Tabs/TabController.swift:1242-1251` already moves tabs between edges from a menu; a playful consolidation path is missing.

Extend the spring-load/drag-hover plumbing to tab pills: dwell on a tab shows a merge halo, and dropping appends the dragged tab's items (keeping the target tab) with an undo toast. Effort: one to two days.

### Pills could lift on hover

novel, delightful, or quirky ideas worth trying — nice-to-have

`MacDring/Tabs/TabStripView.swift:38-63` changes on drop highlights only; a gentle scale/shadow on hover would give pills the same physicality the poof and haptics give actions.

Animate scale/shadow on `onHover`, respecting Reduce Motion. Effort: two to three hours.

### Drag out of group preview tiles

novel, delightful, or quirky ideas worth trying — nice-to-have

`MacDring/Drawer/ItemView.swift:195-205` renders a mini-preview of group children; dragging a child straight out of the preview (to another app) is the natural next step for the iOS-style grouping interactions.

Allow `onDrag` providers for group children in the preview tiles. Effort: one day.

### Make clipboard results legible at narrow drawer widths

ClipboardHistoryView gives a leading icon to every row and a secondary relative date below each two-line snippet. On a narrow drawer the repeated icon costs space and identical first lines make clips hard to distinguish. Prototype one shared clipboard glyph in the header and a reserved trailing selection mark for keyboard navigation. Compare one-column and wide drawers using prose, paths, emoji and code. Retain explicit focus and one spoken action per row. Pick a treatment after checking contrast and scan time with real content. Listen to search excerpts with VoiceOver punctuation verbosity enabled. If truncation markers interrupt speech, omit only the markers generated by the app and preserve punctuation from the clip itself. Compare time to select the correct clip from two long logs with the same header. Try match highlighting only if people still struggle to locate the hit.

### Explain where a matching launcher lives

DrawerSearch flattens groups. Two launchers named the same thing become indistinguishable, especially for bookmarked files with the same basename. Prototype a secondary group or parent-folder label only for colliding names. Keep ordering and drop routing keyed by the original item ID. Verify that two identical names in different groups can be chosen deliberately by sight and by VoiceOver without revealing unrelated full paths.

### Give clipboard users a reversible way to peek

A two-line clip can be difficult to recognize. Activating the row replaces the system clipboard. Prototype Space on a selected clipboard row as a transient read-only text preview inside the drawer. Escape returns to the same selection and scroll position. Evaluate whether the preview is worthwhile after match excerpts ship. Verify no pasteboard write, history mutation, new permissions or external launch. Include long text, clipped lines and a switch to another tab while peeking.

### Add a temporary return tray for a project

**Delightful prototype.** A user selects files across apps and drops references into a small shelf, optionally names the collection, then can reopen it as a normal Items drawer when the collection becomes useful. Offer a session-only tray or an explicit expiry (after a chosen time or the next open). Clearing the tray removes references only. Reuse existing bookmarks, lock rules and drop cues. Prototype return-to-task recovery after a desktop change and give explicit Undo before any reference is discarded.

### Try an optional tab index for crowded edges

**Delightful navigation.** The status menu is a flat list; two same-named tabs on distinct displays are hard to tell apart. Prototype a menu-bar index grouped by display and edge, with an unobtrusive recently used section and stable search labels. Make disconnected tabs explicit and handle duplicate names without changing persisted titles. Compare the 4- and 40-tab cases before adopting a richer interface.

### Give drawers an explicit keyboard focus action

convenience prototype — local to one drawer

Per-tab hotkeys already toggle the drawer. Prototype a separate command that deliberately focuses an open drawer, or opens it with the search field visible even for a short Items listing. Compare a direct shortcut with double-press or an alternate chord and keep routine typing in the frontmost app untouched. For notes, focus the editor. For clipboard, focus the filter. Compare repeated launching from a pinned drawer and deliberate type-to-find in a newly opened drawer.

### Offer clipboard history in the status menu

feature prototype — medium

The status menu already lists tabs. A "Recent Copies" submenu would allow a quick paste without opening a drawer, with no new permission. Bound it to the same store, retention and privacy rules, and keep the menu short.

### Option-click a tab to open every tab on an edge

delight — small

A power-user path that reuses the existing open/close plumbing: Option-click a pill opens every tab on that display and edge (or closes them). Keep the ordinary click unchanged and document the modifier.

### Add quiet hours for Fresh arrival cues

delight — small

Suppress the Fresh pill dot and arrival sparkle during a user-set window. Small, privacy-adjacent, and easy to ignore.

### Give empty drawers a direct action

usability — small

"Drag apps & files here" plus an Add Files… button; "No matches" plus Clear filter; "Folder unreadable" plus Try Again and Choose Folder…. Keep the existing tone and test the narrow header.

### Open a group's items together

missing features — nice-to-have

A group only opens its sub-grid. DragThing users kept "morning apps" sets, and groups are the natural home for them. Add an "Open All" group action, with the count in its title and a confirmation above about eight items, that launches each child through `ItemLauncher` and records Recents. Effort: half a day.

### Hover quick actions on items

prototype — medium

Two or three small buttons (Open, Reveal in Finder, Lock) that fade in at a cell's trailing corner on hover, with 24 pt hit areas; the context menu keeps the full set. Builds on #202's hover state.

### A notes caption

prototype — small to medium

"128 words, 3/5 tasks" under the notes header, derived from `model.notes`, a brief "Saved" after `handleNotesEdit`, and a Copy Markdown header button.

### Show empty slots while dragging

prototype — small

While `dragging != nil`, draw empty grid slots as dashed outlines with a faint plus that brightens under the pointer; static under Reduce Motion.

### Motion and haptics

prototype — small each

A restrained spring on drawer open and pill seating (instant under Reduce Motion); an `.alignment` haptic when a reorder crosses a slot and `.levelChange` when a dwell arms grouping, following `TabDragPolicy`; a short glyph flip on open; one pulse of the Fresh arrival dot. Settle "Make reduced motion coherent across drawer interactions" first.

### Acknowledge a launch on the cell

prototype — small

A brief accent ring, or a 0.94-to-1 scale, on the launched cell, ignoring repeat clicks while the launch is in flight.

### Apply appearance to all tabs

prototype — small to medium

"Apply to All Tabs" in the appearance editor, and "Reset All Settings" (with confirmation) in General.

## Maintenance

### TabController carries most of the app

`MacDring/Tabs/TabController.swift` is about 1,900 lines and owns reconcile, hotkeys, monitors, concealment, drag, drops, launching, eject, watches, Spotlight, Fresh badges, clipboard, undo and the notes flush. Policy types (`TabPlacementPolicy`, `SpringLoadPolicy`, `TabDragPolicy`, `TabCycling`, `HotkeyRegistrationPolicy`) and injected seams (`GlobalHotkeyRegistering`, `TrashServicing`) already isolate many decisions. Extract `ConcealmentController`, `TabDragController` and `FreshMonitor` one at a time, keeping those seams. Not a defect; do it when a change in one of those areas gets hard. Effort: large.

### Build new tabs in one place

`TabsView.addTab`, `NewTabWindowController` and the first-run tab in `AppDelegate` each build a `Tab` from the preferences by hand, and #213 fixed one that had drifted. A small factory taking title, glyph and kind would keep new-tab defaults in one place.

## Notes for future passes

### Claims checked and refuted

Do not raise these again without new evidence:

- Esc or hover-close during an item reorder still applies the drop. The gesture is not cancelled, but `closeDrawer` clears `openTabID` before hiding (`TabController.swift:515`), and `onPlaceItem`, `onGroupItems` and `onPlaceInGroup` all guard on it (:1109-1120).
- Slot frames in `@State` re-render the drawer on every scroll tick. Measured with `Self._printChanges()` in a 214-item folder drawer: two scrolls of 10 and 15 wheel ticks produced no `_slotFrames` change and at most two re-renders, both from icon loads. The macOS `ScrollView` does not re-run layout for scrolled content. Do not change this without a new measurement.
- Dragging a broken item starts an empty drag. `BookmarkResolver.url(for:)` falls back to `item.url`, which the live listers always set.
- Unnamed groups announce an empty VoiceOver label. New groups get `DrawerGrouping.defaultName`, renaming to blank falls back to it, and decoding turns an empty name into "Item" (`DrawerItem.swift:102`).
- A 32-bit size truncation in the update downloader. `NSNumber.intValue` is `Int`. The downloader is now Updraft's.
- The native notes editor resets the document on an external change during input-method composition. `update(_:)` lacks the marked-text guard, but no current path rewrites `model.notes` while the editor is alive: `handleNotesEdit` mirrors the accepted value, refresh preserves live notes, and `TabStore.setNotes` does not notify.
- Enabling clipboard retention after a failed load overwrites the unreadable archive. `setRetention` returns early when the value is unchanged, and the only change path deletes the archive by design first (`ClipboardHistoryStore.swift:43,96-99`).
- Linux system recents are not de-duplicated. `recentsHits` applies `dedupedByURL` for Recents tabs (`TopDrawerService.swift:563-565`).

### Corrections to BACKLOG.md

- A7 says arrows and Return work only while a search query is active. They now work without one: `handleDrawerKey` routes Up, Down and Return, and `moveSelection` and `launchSelection` use the unfiltered items (`DrawerNavigationTests`). Space stays Quick Look without a query, on purpose. The rest of A7 (context actions, accessible states) is still open.

### Checking behavior on a real desktop

- Launch the Debug build with `CFFIXED_USER_HOME` pointing at a scratch directory, so `launcher.json` and the preferences stay out of the real home. Pass typed defaults as launch arguments, for example `-gridColumns '<real>6</real>'`; `Preferences` reads doubles, so a plain string is ignored.
- Set `NSUnbufferedIO=YES` to see `Self._printChanges()` output promptly.
- The pill panel never becomes key, and the drawer panel does, except over another app's full-screen window. Tooltips, key events and first-responder behavior differ between them accordingly.
