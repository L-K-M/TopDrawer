# Top Drawer: remaining review findings

This backlog consolidates several repository reviews, including the MiMo pass. It covers the macOS app and the experimental Linux port. The working scale is one desktop user, dozens of tabs, hundreds of launchers, and occasional large or remote folders. Start with layout recovery, ambiguous identities, and failures that affect user files. Treat appearance and feature proposals as prototypes with the validation described in each entry.

The latest pass reviewed main at `c905100` and inspected the current AppKit and SwiftUI paths, persistence, live listings, shared models, Linux volume parsing, tests, and the supplied screenshot. The combined changes passed 636 macOS tests. The Linux volume fixes passed the focused volume suite in a Swift 6.3 Noble container. Performance claims without results are hypotheses. Live multi-display, Spaces, VoiceOver, compositor, and Instruments checks remain to be run. EditorWeb is a standalone harness; its runtime was outside this pass.

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

A further pass opened four focused fixes: a bounded update-download session so a stalled transfer cannot pin `isDownloading` for the default seven-day resource timeout ([#207](https://github.com/L-K-M/TopDrawer/pull/207)); pagination for the prerelease release scan under a documented page budget ([#208](https://github.com/L-K-M/TopDrawer/pull/208)); folder popovers opening inward from the drawer's own edge ([#211](https://github.com/L-K-M/TopDrawer/pull/211)); and a dangling-symlink collision check in `FileMover` ([#216](https://github.com/L-K-M/TopDrawer/pull/216)).

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

### A second update check can double the daily timer

bugs — nice-to-have

`MacDring/Updates/UpdateChecker.swift:91` lacks the `timer == nil` guard that `ClipboardMonitor.start()` has. A second call installs a second daily timer and doubles update checks.

Add `guard timer == nil else { return }`. Effort: trivial. Implemented in [#192](https://github.com/L-K-M/TopDrawer/pull/192).

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

### A hotkey press can fire once after unregister

general issues — nice-to-have

`MacDring/Hotkeys/CarbonHotkey.swift:59`: `DispatchQueue.main.async { me.onPressed?() }` captures `me` strongly, so a queued press fires after `unregister()` — a stale hotkey acts on a dead registration.

Capture weakly or check `hotKeyRef != nil` inside the block. Effort: trivial. Implemented in [#192](https://github.com/L-K-M/TopDrawer/pull/192), which captures the exact `EventHotKeyRef` and compares it on the main queue so a re-register on the same instance cannot let a queued press through.

### A transient bus restart permanently kills the daemon

general issues — nice-to-have

`linux/Sources/TopDrawerDaemon/Daemon.swift:223-235`: a failure inside `withSessionBus`'s closure and a failure to connect share the same `exit(1)`, so a transient bus restart kills the daemon instead of reconnecting.

Distinguish connect failure (retry with backoff) from service failure, or document a required systemd `Restart=`. Effort: small.

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

### Scan the intended prerelease history

bug — relevant when prerelease checking is enabled

`GitHubReleaseClient` picks the highest version from the first 30 releases. When publication order differs from version order, a higher-version prerelease can sit on an older page. Define the supported history window or follow pagination with a bounded request policy and a test for out-of-order version tags. In review: [#208](https://github.com/L-K-M/TopDrawer/pull/208) follows 100-entry pages to a 10-page budget, stops on a short page, and picks the maximum non-draft version.

### Keep per-path icon overrides from attaching to unrelated files

general issue — respect transient listing limits

`TabStore` retains the path-keyed overrides for live rows. A repointed folder can keep irrelevant styles indefinitely; a later file that reuses a path can pick up an old style. Clear or explicitly migrate revision-specific styles on folder replacement. Investigate durable file identity before pruning on refresh: caps, hidden-file filters and a temporarily unavailable volume can all hide a still-valid item. Test a rename, path reuse, folder replacement, and partial listings.

### Separate durable tab identity from immediate availability

**Bug and usability.** AppDelegate's menu suggests it opens tabs even when parked on a disconnected display. `TabController.openDrawer` requires a resolved screen and a live pill. An enabled row then performs no visible action. Build menu rows from the same placement state the controller uses. For parked tabs, show their state and route to placement settings, or offer a separately designed temporary opening that leaves the saved anchor intact. Verify disconnect and reconnect, an already-open drawer, and the move-to-main setting. This complements the backlog's portable import display mapping.

### A fetched favicon can override the shared store's link icon

reliability / icon precedence — nice-to-have

`ItemView.resolveIcon` returns the shared Pict icon for a `.url` item (precedence rung 3), but the resolution `.task` then replaces it with a fetched favicon whenever the item has no image or generated-style override. The favicon is the kind-specific default (rung 5), so a link with a shared icon set is demoted to its site favicon. Gate the fetch on the shared lookup, and reuse that lookup rather than resolving the target twice. In review: [PR #193](https://github.com/L-K-M/TopDrawer/pull/193). Effort: small.

### Unknown SF Symbol names blank the tab pill

visual / forward compatibility — nice-to-have

`TabStripView.glyphView` draws `Image(systemName: name)` with no fallback. A document written by a newer build (or hand-edited) can carry a symbol this OS does not know, leaving an empty glyph on an otherwise colored pill. `IconName` only maps names for Linux; macOS renders the stored name unchanged. Fall back to `TabGlyph.default` when the symbol cannot be resolved, and cover it at the name-resolution layer. Effort: small.

### A move can target a dangling symlink

reliability — small

`FileMover.uniqueDestination` tests the destination with `fileExists(atPath:)`, which is false for a dangling symlink in the destination directory. `moveItem` then fails or replaces the link. Check `fileExists(atPath:isDirectory:)` and link existence, or catch the move failure and step to the next candidate. Add a test with a broken symlink in the destination directory. Effort: small. In review: [#216](https://github.com/L-K-M/TopDrawer/pull/216) treats any symlink as occupying the name via `destinationOfSymbolicLink` and leaves the link intact.

## Performance and responsiveness

### Settings resolves file icons inside its render path (SOL-14)

performance problems, stuttering, and jank — important

`MacDring/Settings/TabsView.swift:304-307` calls icon resolution during each body evaluation. `MacDring/Drawer/ItemView.swift:213-228,495-574` shows that this work resolves bookmarks and reads icons from disk. Large launchers, stale bookmarks, or remote targets can beachball Settings repeatedly.

Resolve row icons asynchronously, keyed by the item, with a placeholder and cancellation. Reuse the drawer's resolution approach. Profile opening and changing settings for a 100-entry tab. Effort: half a day. Implemented in [#194](https://github.com/L-K-M/TopDrawer/pull/194): an `AsyncItemIcon` reuses `ItemView.resolveIcon` off the render path with a cancellation handler.

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

### Shortcut recording consumes keys after defocus (SOL-24)

usability: speed, convenience, and clarity — important

`MacDring/Settings/HotkeyRecorderView.swift:24,37-52` keeps its app-wide local key monitor armed until capture, cancellation, or disappearance. Click Record Shortcut, then click Name and type: ordinary keys vanish, while a later usable command can unexpectedly become the hotkey.

Scope capture to a focused recorder and cancel on focus/window loss or outside click. Verify text entry, normal shortcuts, and window switching. Effort: half a day plus AppKit verification.

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

### Rejected hotkey combos fail silently

usability: speed, convenience, and clarity — nice-to-have

`MacDring/Settings/HotkeyRecorderView.swift:51`: unusable combos (Shift-only, bare letters) are silently consumed while recording — the user gets no hint why nothing registered.

Show a brief inline hint ("needs ⌘/⌃/⌥ or a function key"). Effort: small.

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

### New-tab actions fail silently without a display

usability: speed, convenience, and clarity — nice-to-have

`MacDring/Settings/NewTabWindowController.swift:44-46` and `MacDring/Settings/TabsView.swift:133-139` silently return when `registry.mainScreenUUID()` is nil, so the "+" button or dialog does nothing with no explanation.

Surface a short explanatory alert instead of a silent no-op. Effort: one hour.

### The header truncation badge is a dead end

usability — capped Folder listings

`DrawerView.header` shows a count such as 300+ when `FolderLister` has more entries than its cap. The tooltip explains the cap, and the existing Finder action can reach every file. Give the cap an accessible label and clearly connect it to the Finder action. Test both exactly 300 results and a capped folder on a narrow drawer.

### Test interrupted closes as well as opens

DrawerWindowController.show guards its animation completion with presentationGeneration. The animated hide checks isVisible alone. Exercise close A, reopen B, close B before A finishes. Record whether A's completion can remove B's panel early, clear its rows or reset opacity during the second fade. If reproducible, bind close cleanup to its originating generation. Check zero-duration switches, the riding pill and Reduce Motion.

### Paste into a drawer to create launchers

usability — keyboard workflow

Settings already offers an Add Link sheet. Direct paste into an Items drawer could add a URL or file reference without leaving the drawer. Define how plain non-URL text should be handled before expanding support beyond file URLs and links. Fetch clipboard contents only on the deliberate action. Respect editable text focus, item locks, and the existing drop deduplication policy. Verify that a paste into notes or the filter still edits the focused field.

### Offer update download progress, cancellation, and completion feedback

usability — make the transfer state visible

`UpdateChecker.downloadAndReveal` tracks a Boolean, then reveals the download in Finder or opens the release page on failure. The user has no explicit progress or cancel action and receives little feedback while waiting. Give the transfer a visible state with completion and failure details. Consider an explicit timeout budget in addition to URLSession defaults. Test a slow server, cancellation before and during transfer, temporary file cleanup, and the browser fallback. The timeout half is in review: [#207](https://github.com/L-K-M/TopDrawer/pull/207) gives the downloader its own session with a 60 s request and 5 min resource timeout; progress and cancellation remain open.

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

### Remember a drawer's scroll position per tab

missing feature — nice-to-have

A folder or list drawer with more rows than fit reopens at the top. Store the last scroll offset (or first visible item id) per tab and restore it on reopen, clearing it when the listing changes length or the tab is repointed. Verify a capped folder, a search result list and a notes drawer.

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

`MacDring/Model/ColorHex.swift:62-65` chooses foreground from tint luminance, while `MacDring/Tabs/TabStripView.swift:96-111` renders idle fill at 62% opacity. A middle-dark tint selects white text, but bright underlying content can reduce contrast. This is a source-derived visual risk, not a measured current-screen contrast failure.

Use a sufficiently opaque label backing or a tested composited palette. Check light, dark, and busy wallpapers. Effort: half a day.

### Appearance choices lack a live contextual preview (SOL-27)

aesthetics and theming — nice-to-have

`MacDring/Settings/TabAppearanceEditor.swift:7-32` offers presets, hidden labels, and typography without a representative preview. Users must repeatedly open a drawer to judge those choices.

Add a small tab-and-items preview using the existing view styles, bound to the same settings values. Effort: one day.

### Folder popover always prefers the right side

visual issues and layout problems — nice-to-have

`MacDring/Drawer/FolderBrowserController.swift:23` always prefers `.maxX` regardless of drawer edge; on right-edge drawers it flips at the screen boundary and on top/bottom drawers may detach entirely.

Pick the preferred edge pointing inward from the drawer's edge. Effort: small. In review: [#211](https://github.com/L-K-M/TopDrawer/pull/211) derives `.maxX/.minX/.minY/.maxY` from the drawer's edge and passes it from `DrawerWindowController`.

### Disconnected displays are indistinguishable in the picker

visual issues and layout problems — nice-to-have

`MacDring/Settings/TabsView.swift:512` labels every missing display "Disconnected display"; with several, the user can't tell them apart.

Include a UUID suffix or last-known name in the fallback label. Effort: trivial.

### Fresh-item sparkle replays on every reopen

visual issues and layout problems — nice-to-have

`MacDring/Drawer/DrawerWindowController.swift:306-307`: `sparklingItemIDs` persists until the next apply and the animation runs once per `onAppear`, so a freshly landed item re-sparkles each reopen within its five-minute window.

Clear sparkling ids after the animation completes. Effort: small.

### Tabs cannot follow the system accent color

aesthetics and theming — nice-to-have

`MacDring/Model/Preferences.swift` fixes the default tab color at `#0A84FF` with no "follow system accent" option, so tabs can't match the Mac's accent.

An "Accent" color choice resolving `NSColor.controlAccentColor`. Effort: small.

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

### Generated icons drop their glyph on unknown symbol names

aesthetics and theming — nice-to-have

`MacDring/Common/IconRenderer.swift:55-63` silently skips drawing when `iconStyle.symbol` fails to resolve (corrupted document, or an SF Symbol retired by an OS update), leaving user-styled icons as bare tiles.

Fall back to the kind's default glyph (or a neutral placeholder) when the symbol lookup fails. Effort: one hour.

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
