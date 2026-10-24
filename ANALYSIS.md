# Top Drawer: remaining review findings

Consolidated from two review passes of the repository, most recently against
`origin/main`. Assumed load: one desktop user, dozens of tabs, hundreds of
launcher entries, and occasional large or remote folders. The experimental
Linux port is included.

All eight focus areas were covered. No blocking finding was established.
Findings implemented in an open PR are omitted. Remaining findings follow
severity order, grouped by focus area.

macOS layout, focus, VoiceOver, multi-display behavior, and Linux compositor
interactions need on-device verification. The retained EditorWeb harness is not
the shipping notes editor; its runtime was not audited.

### Duplicate layout identities make entries ambiguous (SOL-02)

bugs — important

`MacDring/Store/TabStore.swift:133-145,302-316` accepts duplicate identities. `MacDring/Tabs/TabController.swift:237-240` gives two tabs sharing a UUID one window. Duplicate item UUIDs within a tab make edits and drop targets select an ambiguous entry, including children in groups. This affects imported or hand-edited layouts.

Reject duplicate tab IDs and per-tab item/container IDs before accepting a document. Failed import must retain the existing layout; invalid on-disk originals must survive recovery. The same item UUID in different tabs can remain valid because operations include tab identity. Add import and recovery regressions. Effort: about half a day.

### Partial launcher recovery can become permanent data loss (SOL-03)

bugs — important

`MacDring/Model/LauncherDocument.swift:24-25` and `MacDring/Model/Tab.swift:133-135` drop unreadable records. `MacDring/Store/TabStore.swift:141-145,799-801` accepts a partially recovered document; successive autosaves eventually replace both primary and backup with that reduced document. Reproduce with one valid tab and one invalid anchor, then mutate and save twice.

Retain a recovery original whenever decoding loses records and expose that recovery before accepting destructive rewrites. Preserve working tabs while making omissions visible. Effort: one day.

### Linux mount escaping corrupts non-ASCII names (SOL-05)

bugs — important

`linux/Sources/TopDrawerDaemon/LinuxVolumes.swift:50-67` appends individual UTF-8 bytes as Unicode scalars whenever a field contains an escape. A mount named `Clé\040USB` becomes `ClÃ© USB`; displayed paths and network/cloud unmount targets become invalid. Accented and non-Latin mount names containing escaped characters are affected.

Accumulate decoded bytes, then decode UTF-8 once. Bound octal conversion so malformed escapes cannot trap. Add mixed Unicode/escape fixtures. Effort: about one hour.

### Filing onto a closed folder pill loses Undo (SOL-06)

bugs — important

`MacDring/Tabs/TabController.swift:940-942,1469-1485` moves files and creates Undo before opening the destination drawer. `MacDring/Drawer/DrawerWindowController.swift:378-385` then clears that action. Users filing through a closed folder pill must reverse the move manually.

Associate the move result with the destination session and publish Undo after opening that drawer. Verify a closed destination and a different drawer already open. Effort: half a day.

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

### Settings resolves file icons inside its render path (SOL-14)

performance problems, stuttering, and jank — important

`MacDring/Settings/TabsView.swift:304-307` calls icon resolution during each body evaluation. `MacDring/Drawer/ItemView.swift:213-228,495-574` shows that this work resolves bookmarks and reads icons from disk. Large launchers, stale bookmarks, or remote targets can beachball Settings repeatedly.

Resolve row icons asynchronously, keyed by the item, with a placeholder and cancellation. Reuse the drawer's resolution approach. Profile opening and changing settings for a 100-entry tab. Effort: half a day.

### Portable imports have no display mapping (SOL-16)

missing features — important

`MacDring/Settings/TabsView.swift:108-124` imports foreign display UUIDs unchanged. Under the default policy, `MacDring/Screens/TabPlacementPolicy.swift:31-35` parks every tab whose display is unknown. Users moving layouts between Macs can get an apparently empty launcher, and the enabled status-menu rows cannot open the parked drawers.

Map unknown imported displays to a chosen connected display. Keep same-machine restoration separate from portable import. Verify an export from another display UUID set. Effort: one day.

### Deleting a notes tab has no recovery step (SOL-17)

missing features — important

`MacDring/Settings/TabsView.swift:151-154`, `MacDring/Tabs/TabStripView.swift:59-61`, and `MacDring/Store/TabStore.swift:168-174` remove an unlocked tab immediately. One Remove Tab action destroys all its note text, without confirmation or document Undo.

Confirm deletion of nonempty notes/populated tabs or offer document-level Undo. Preserve the lock rules and verify both deletion surfaces. Effort: half a day for confirmation, longer for shared Undo.

### A maximum-size drawer can push its pill off-screen (SOL-20)

visual issues and layout problems — important

`MacDring/Drawer/DrawerMetrics.swift:135-136` allows an items drawer to consume screen depth minus 16 points. The riding pill is at least 24 points thick, and `MacDring/Screens/EdgeLayout.swift:160-180` adds it and a 22-point animation nudge outside that allowance. Unlike notes at `DrawerWindowController.swift:510-517`, large items drawers can strand the close target or spill onto an adjacent display.

Bound one combined drawer/pill/animation envelope for every edge. Add pure containment cases for small visible frames, then check real display behavior. Effort: half a day plus macOS verification.

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

### Web-editor remnants mislead and ship dead code (SOL-11)

general issues — nice-to-have

`MacDring/Notes/NotesEditorWebView.swift` and `NotesEditorSchemeHandler.swift` are no longer referenced since the notes editor moved to `NotesEditorNativeView`, yet remain compiled; the EditorWeb docs also still describe the web editor as a shipping integration. Dead paths still compile and are still reviewed.

Delete the unreferenced app-target files and correct the docs; keep `EditorWeb/` and the pure `NotesEditorBridge`/`HostSession` (still tested). Effort: small.

### Broken launchers have no Relink action (SOL-18)

missing features — nice-to-have

`MacDring/Drawer/ItemView.swift:113-192` dims missing targets but provides no Relink action. When both bookmark and fallback fail, users must delete and re-add the item, losing placement, name, and customization.

Offer a file picker that replaces only the target/bookmark after validating its kind, through the existing store/service boundary. Effort: half a day.

### Keyboard navigation does not expose item actions (SOL-19)

missing features — nice-to-have

`MacDring/Tabs/TabController.swift:1814-1847` handles arrows, Return, and Space, but the actions in `MacDring/Drawer/ItemView.swift:127-192` remain mouse-oriented. Keyboard-only users cannot invoke Rename, Lock, Reveal, Open With, or Eject through the current selection.

Add a selected-item actions shortcut and accessible named actions. Effort: one day plus assistive-technology checks.

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

### Explain the pending drop before releasing it (SOL-28)

novel, delightful, or quirky ideas worth trying — nice-to-have

`MacDring/Drawer/DrawerWindowController.swift:66-77` and `MacDring/Drawer/DrawerView.swift:397-436` show a target ring without explaining the pending action. New users must remember whether a tile opens, files, trashes, or adds a launcher.

After a brief dwell, show target-specific text such as “Move to Downloads” or “Open with Preview,” using the same operation policy as the cursor. Test whether it reduces hesitation without obscuring the target. Effort: half a day after SOL-25.

### Offer non-destructive starter drawer kits (SOL-29)

novel, delightful, or quirky ideas worth trying — nice-to-have

`MacDring/AppDelegate.swift:274-328` supplies Apps/Welcome. Useful Folder/Fresh/Notes combinations still require manual discovery; the import flow at `MacDring/Settings/TabsView.swift:108-124` replaces the entire layout.

Offer a few optional local kits, such as “Downloads desk” with Folder, Fresh, and Notes, added without replacing current tabs and removable in one action. Reuse existing tab types; no automation or permissions are needed. Effort: one to two days.

### A second update check can double the daily timer

bugs — nice-to-have

`MacDring/Updates/UpdateChecker.swift:91` lacks the `timer == nil` guard that `ClipboardMonitor.start()` has. A second call installs a second daily timer and doubles update checks.

Add `guard timer == nil else { return }`. Effort: trivial.

### Spotlight hit URLs are not standardized before dedupe

bugs — nice-to-have

`MacDring/Store/SpotlightQuery.swift:337` builds hits with `URL(fileURLWithPath:)` unstandardized while `FreshScanner` standardizes, so `FreshLister.merge` can show the same file twice via symlinked/real paths.

Standardize the hit URL at construction in `SpotlightQuery.results`. Effort: small.

### Recents dedupe is case-sensitive on case-insensitive volumes

bugs — nice-to-have

`MacDring/Store/RecentsStore.swift:45-46` dedupes by `URL` equality, which is path-case-sensitive. The same file opened as `/X` and `/x` leaves duplicate recents.

Compare `standardizedFileURL` or a lowercased path. Effort: small.

### Trash looks empty on filesystems without entry counts

bugs — nice-to-have

`MacDring/Store/TrashInspector.swift:64-70`: without `ATTR_DIR_ENTRYCOUNT` the `linkCount <= 2` fallback only counts subdirectories, so a Trash holding only files reports empty — wrong icon, disabled "Empty Trash" on exotic or remote volumes.

Treat the fallback as non-empty or probe one directory entry. Effort: small.

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

Capture weakly or check `hotKeyRef != nil` inside the block. Effort: trivial.

### Update downloads have no timeout or cancel path

general issues — nice-to-have

`MacDring/Updates/UpdateDownloader.swift:46`: `URLSession.download(from:)` on the shared session sets no request timeout, so a stalled transfer leaves `isDownloading` true forever.

Set a request or session `timeoutInterval`. Effort: trivial.

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

### Per-tab thickness re-measures text every layout pass

performance problems, stuttering, and jank — nice-to-have

`MacDring/Common/DrawerAppearance+SwiftUI.swift:28` runs an NSString text measurement for every tab on every layout pass — small but repeated hot-path work.

Cache the measured line height keyed on (title, font, weight). Effort: small.

### Every DocumentChanged signal triggers a full refetch

performance problems, stuttering, and jank — nice-to-have

`linux/Sources/TopDrawerShell/DaemonClient.swift:383-397`: each `DocumentChanged` fires an immediate `fetchTabs` with no debounce, so a burst of saves means one `GetDocument` round-trip per signal.

Coalesce fetches (skip if one ran within ~200ms or is in flight). Effort: small.

### Empty-Trash state is statted inside the menu builder

performance problems, stuttering, and jank — nice-to-have

`MacDring/Drawer/ItemView.swift:148`: `TrashInspector.trashIsEmpty()` runs a synchronous per-volume stat sweep when the context menu opens — a spun-down or network volume stalls presentation.

Resolve asynchronously like other item metadata. Effort: small.

### Clipboard history saves on the main thread

performance problems, stuttering, and jank — nice-to-have

`MacDring/Store/ClipboardHistoryStore.swift:113`: `saveNow` JSON-encodes and atomically writes the whole history on the main thread; a worst-case history is a multi-MB write that can hitch the UI.

Encode and write off-main or cap the serialized size tighter. Effort: small.

### Removing a drawer item has no Undo

missing features — nice-to-have

`MacDring/Drawer/ItemView.swift:191`: item removal is permanent; the undo-toast infrastructure exists for file moves but not item removal.

Reuse `DrawerUndo` for a "Removed X — Undo" toast. Effort: medium.

### Clipboard history captures plain text only

missing features — nice-to-have

`ClipboardMonitor.captureChanges` reads only `.string`; images, files, and rich text are invisible. Users coming from Paste or Maccy expect image and file entries.

Record a bounded set of types (thumbnail images, file URLs as items) behind the existing opt-in. Effort: medium-large.

### Clipboard entries cannot be pinned

missing features — nice-to-have

A frequently-needed snippet ages out after 50 copies with no way to keep it.

Add pin/favorite entries that survive clearing. Effort: medium.

### No keyboard path to add a URL item

missing features — nice-to-have

A `.url` item can only be created by dragging a link; there is no paste/⌘V or "Add Link…" path, so a clipboard URL can't be added without a browser drag.

Accept ⌘V on a focused items drawer or add an "Add Link" affordance. Effort: small-medium.

### Drawer items cannot be dragged out

missing features — nice-to-have

Items in an `.items` drawer can be reordered or grouped but never dragged out to Finder, another app, or the Trash item — DragThing users expect drag-out-to-move.

Add `.onDrag` to item cells alongside the reorder gesture (in-drawer reorders, drag-out exports the URL). Effort: medium.

### No way to search across all tabs

missing features — nice-to-have

Type-to-find only searches the open drawer; there is no global search across tabs.

A global filter (hotkey or dedicated Search tab) aggregating every tab's items. Effort: medium-large.

### Folder popover always prefers the right side

visual issues and layout problems — nice-to-have

`MacDring/Drawer/FolderBrowserController.swift:23` always prefers `.maxX` regardless of drawer edge; on right-edge drawers it flips at the screen boundary and on top/bottom drawers may detach entirely.

Pick the preferred edge pointing inward from the drawer's edge. Effort: small.

### Disconnected displays are indistinguishable in the picker

visual issues and layout problems — nice-to-have

`MacDring/Settings/TabsView.swift:512` labels every missing display "Disconnected display"; with several, the user can't tell them apart.

Include a UUID suffix or last-known name in the fallback label. Effort: trivial.

### Fresh-item sparkle replays on every reopen

visual issues and layout problems — nice-to-have

`MacDring/Drawer/DrawerWindowController.swift:306-307`: `sparklingItemIDs` persists until the next apply and the animation runs once per `onAppear`, so a freshly landed item re-sparkles each reopen within its five-minute window.

Clear sparkling ids after the animation completes. Effort: small.

### Rejected hotkey combos fail silently

usability: speed, convenience, and clarity — nice-to-have

`MacDring/Settings/HotkeyRecorderView.swift:51`: unusable combos (Shift-only, bare letters) are silently consumed while recording — the user gets no hint why nothing registered.

Show a brief inline hint ("needs ⌘/⌃/⌥ or a function key"). Effort: small.

### Space does nothing before a selection exists

usability: speed, convenience, and clarity — nice-to-have

`MacDring/Drawer/DrawerModel.swift:192-200`: Space previews only after the user arrow-keys a selection; `launchSelection` falls back to the top result but preview doesn't, so Space looks dead on a fresh search.

Apply the same top-result fallback as launch. Effort: trivial.

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

Only renumber what changed. Effort: small.

### Web launches land in Linux recents as empty rows

usability: speed, convenience, and clarity — nice-to-have

`linux/Sources/TopDrawerDaemon/RecentsRecorder.swift` + `LinuxRecents.swift` (`RecentEntry.init`): `Launch` records non-file kinds into recents and emits `url.path`, which is empty for `https://` hits — useless empty-path rows.

Skip non-file kinds or emit the full URL. Effort: small.

### Tabs cannot follow the system accent color

aesthetics and theming — nice-to-have

`MacDring/Model/Preferences.swift` fixes the default tab color at `#0A84FF` with no "follow system accent" option, so tabs can't match the Mac's accent.

An "Accent" color choice resolving `NSColor.controlAccentColor`. Effort: small.

### The group preview tile is invisible on light backings

aesthetics and theming — nice-to-have

`MacDring/Drawer/ItemView.swift:339` tints the iOS-style group tile fixed `.white.opacity(0.16)`; over the light appearance's solid/frosted backing it's subtle-to-invisible.

Derive the tint from `Color.primary` or the tab color. Effort: small.

### A Shelf tab for transient drops

novel, delightful, or quirky ideas worth trying — nice-to-have

A drop-zone drawer that holds dragged-in files temporarily and auto-empties after N minutes or on next open — DragThing-adjacent, low risk, high charm.

New tab kind with a timed or session-scoped listing. Effort: medium.

### Badge counts on the tab pill

novel, delightful, or quirky ideas worth trying — nice-to-have

Per-tab counts on the pill itself — Fresh shows "3" for newly landed files, a watched folder shows pending items — glanceable without opening.

A badge overlay driven by the live listing counts. Effort: medium.

### Shell-command items

novel, delightful, or quirky ideas worth trying — nice-to-have

A drawer item that runs a small script and copies the result — clipboard-friendly workflows without leaving the drawer.

New item kind with a bounded subprocess runner. Effort: medium-large.

### Paste-to-create items

novel, delightful, or quirky ideas worth trying — nice-to-have

⌘V into a focused items drawer turns clipboard text/URL/files into items — rounds out the missing add-URL-by-keyboard gap.

Pasteboard handling on the drawer's key path. Effort: small-medium.

### An edge-glow pulse on listing changes

novel, delightful, or quirky ideas worth trying — nice-to-have

A subtle edge-glow pulse on the pill when a watched folder or Fresh listing gains items — ambient notification without a badge.

A brief pill highlight driven by the existing watch callbacks. Effort: small.
