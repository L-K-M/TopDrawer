# fable-is-awesome.md — a fresh review of MacDring

*Reviewed at `main` @ `3803678` (v1.8.0), 2026-07-02. Method: an eight-agent review
fan-out (per-subsystem and per-dimension finders) combined with a full first-hand read
of every file under `MacDring/`, then line-level verification of each finding.
Everything here is cross-checked against `awesome.md` and `ANALYSIS.md` so it does
**not** duplicate the already-tracked backlog — where a known item appears, it's
because there is material new evidence. IDs: `FB` bugs · `FP` performance · `FV`
visual · `FU` UX · `FF` missing features · `FI` ideas.*

*The **Status** column is updated as items are implemented (one branch/PR per item,
grouped only where two items share the same lines of code).*

---

## 1. Bugs

### FB1 🔴 The Fresh tab triggers macOS permission prompts — breaking the app's core "no permissions" promise — *critical*
`FreshScanner.results` calls `FileManager.contentsOfDirectory` (plus per-entry
`resourceValues`) directly on `~/Downloads`, `~/Desktop`, and `~/Documents`
(`MacDring/Store/FreshScanner.swift:32`, scopes from `FreshLister.scopes()`). All
three folders are TCC-protected on every macOS this app targets — for non-sandboxed
apps too. Consequences:

- **Prompts with zero user action.** At launch, `reconcile → updateFreshBadgeTimer →
  refreshFreshBadges` (`TabController.swift:1115`) runs the scan on a background queue
  whenever a Fresh tab merely *exists* — up to three "MacDring would like to access
  files in your Downloads folder" dialogs appear out of nowhere, and the 60 s badge
  timer keeps poking until answered.
- **The drawer can freeze behind the dialog.** `DrawerWindowController.apply`
  (`:325`) runs the same scan *synchronously on the main thread* at drawer open.
- **Denial silently guts the feature.** `try?` swallows the failure; the Fresh tab
  quietly degrades to Spotlight-only — the exact dependency the direct scan was built
  to remove.

This contradicts README ("no special permissions"), AGENTS.md's hard constraint, and
the Fresh tab's own Settings copy ("No special permission needed"). The codebase
elsewhere goes to heroic lengths to avoid exactly this (see `TrashInspector`'s
metadata-only counting). **Fix:** make the Fresh pipeline Spotlight-only again
(drawer fill and pill-dot via `SpotlightQuery`, which reads the index and never
prompts); keep `FreshScanner` as tested pure logic out of the default path.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB2 🔴 De-overlap pass permanently rewrites stored tab positions from transient states — *high*
`persistSettledPosition` (`TabController.swift:210`) writes every de-overlap snap back
into the tab's stored anchor, on every reconcile, against whatever screen the pill
currently sits on. Under `disconnectPolicy == .moveToMain`, a tab whose display is
disconnected gets placed on the primary display, snapped clear of the tabs there, and
its **stored fraction is overwritten while `displayUUID` still names the external
display** — reconnect the display and the tab restores to the corrupted position.
Transient geometry (Dock reveal/resize, resolution switches mid-reconfiguration) can
do the same on a single display. This violates AGENTS.md's "stable restore is sacred."
**Fix:** persist a settled position only when the tab is actually sitting on its own
anchored display.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB3 🔴 Hotkey recorder accepts Shift-only shortcuts, which then swallow ordinary typing system-wide — *high*
`KeyCodes.hasModifier` counts Shift alone as a sufficient modifier
(`Hotkeys/KeyCodes.swift:76`), and both the recorder
(`HotkeyRecorderView.swift:44`) and registration (`TabController.swift:787`) rely on
it. Record ⇧A as a tab hotkey and every attempt to type a capital "A" — in any app —
toggles a drawer and swallows the keystroke. **Fix:** require ⌘/⌃/⌥ for ordinary
keys; while in there, *allow bare function keys* (F1–F20) — a real DragThing-style
convenience the backlog already wants (`awesome.md §4`), and safe because F-keys
don't collide with typing.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB4 🟠 One bad record wipes the entire Recents history — *medium*
`RecentsStore.load` decodes with a strict all-or-nothing
`try? JSONDecoder().decode([RecentItem].self,…)` (`Store/RecentsStore.swift:64`): one
undecodable record — e.g. an `ItemKind` raw value written by a newer MacDring — nils
the whole array, and the next `record()` **persists the wipe**. The launcher document
learned this exact lesson (`FailableTab` / `FailableDrawerItem` / `decodeLenient`);
the recents store didn't get the memo. **Fix:** per-element failable decoding + a
lenient `kind` fallback.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB5 🟠 Favicon fetch overwrites a URL item's user-chosen custom icon — *medium*
`ItemView`'s `.task` (`Drawer/ItemView.swift:126`) fetches a favicon for every `.url`
item *unconditionally* and assigns it over whatever `resolveIcon` returned — including
a user-set image (`customIconBookmark`) or generated icon (`iconStyle`), which
`resolveIcon` correctly prefers. Customize a link's icon and the favicon stomps it a
beat later. **Fix:** skip the fetch when either override is set.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB6 🟠 The Undo toast survives drawer close/switch — Undo then acts on another tab's files — *medium*
`model.undoToast` is cleared only by its 6-second timer or a click
(`TabController.swift:1032`); `DrawerWindowController.apply/hide` reset five other
transient fields but not this one (nor `ejectingItemIDs`). Drop files into folder tab
A, click tab B within 6 s: B's drawer opens showing A's "Moved 3 items — Undo", and
pressing Undo silently moves A's files back while you look at B. **Fix:** clear the
toast (and eject-spinner state) whenever the drawer loads a tab or hides; cancel the
timer on close.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB7 🟠 Bookmark self-healing skips folder tabs and custom icons — *medium*
`TabStore.remintStaleBookmarks` (`Store/TabStore.swift:174`) sweeps only
`item.bookmark`. `Tab.folderBookmark` (the directory a folder tab mirrors) and
`DrawerItem.customIconBookmark` (custom icon images) never get re-minted, so those go
stale forever the same way item bookmarks used to. **Fix:** extend the sweep to both.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB8 🟠 Drag-over "peek" fires on any left-button drag — and polls the pasteboard per event — *medium*
`fileBeingDragged()` (`TabController.swift:469`) gates the generous peek-reveal zone
on "left button down + drag pasteboard holds file URLs". But the drag pasteboard
**retains the previous drag's contents**, so after the first file drag of the session,
*any* left-drag — moving a window, selecting text — passes the check and pops concealed
tabs out at 60 pt range. Compounding it, the check does an out-of-process pasteboard
read at the top of `evaluateConcealment`, i.e. per `leftMouseDragged` event
system-wide while any concealable tab exists. **Fix:** stamp the drag-pasteboard
`changeCount` on mouse-down and treat a drag as a file drag only when the count has
advanced since (a real drag session writes the pasteboard *after* the press); consult
the pasteboard only when the cursor is actually near a peek zone, cached per
`changeCount`.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB9 🟠 Folder-tab slot drops re-list the directory — the target can differ from what's on screen — *medium*
`handleFileDrop` (`TabController.swift:712`) resolves the drop-target slot against a
**fresh** `FolderLister.contents(of:)` listing rather than the items the drawer is
showing. If the directory changed since the drawer rendered (or sort order shifts),
the slot the user aimed at can resolve to a different item — filing files into the
wrong folder — and every drop pays a full re-list. **Fix:** resolve slot targets from
`drawer.model.items` when that tab's drawer is open (slots only exist on screen
anyway).
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB10 🟠 Read-only tab pills advertise file drops, then silently discard them — *medium*
Every pill registers for `.fileURL` drops (`TabStripView.swift:232`) and shows the
bright drop-target ring, but `handleFileDrop` discards drops on notes / disks /
network / cloud / recents / fresh tabs with no feedback (`TabController.swift:736`).
PR #58 fixed this for *web URL* drops; file drops still lie. **Fix:** a
`TabStripModel.acceptsFileDrops` flag driven by tab kind — only items/folder pills
register for file drops.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB11 🟠 Rename / Change Icon / Empty Trash dialogs can open *beneath* the drawer while app-modally blocking it — *medium*
The drawer panel floats at `.popUpMenu` level; `renameItem`, `changeItemIcon`, and
`emptyTrash` (`TabController.swift:892–946`) run window-level-default modals without
closing the drawer or raising the dialog's level (`customizeIcon` closes the drawer
first; these don't). A large drawer can cover the centered alert: the app is modal,
the drawer eats the clicks, the prompt is invisible. **Fix:** float the dialog above
the drawer level (and add the Trash item count to the Empty Trash message while
there — Finder tells you how many items you're about to erase; see FU3).
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB12 🟡 Launch-at-Login toggle can show "on" while macOS is still waiting for approval — *medium, needs device*
`systemLaunchAtLoginEnabled()` maps `.requiresApproval` to `nil` → the stored default
(`Model/Preferences.swift:208`), so a registration parked in System Settings →
Login Items shows as enabled while it isn't running. Needs on-device verification of
`SMAppService` state transitions before changing; surface `.requiresApproval` as its
own message ("waiting for approval in System Settings").

### FB13 🟡 Eject All spinners vanish after the first volume unmounts — *low (root cause: FP3)*
`ejectingItemIDs` is keyed by item UUID; the unmount notification refreshes the
listing, which rebuilds every transient item **with a fresh UUID**
(`TabController.swift:1005`), so the remaining in-flight spinners drop off.
Fixed by stable transient IDs (FP3).
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB14 🟡 The "one-shot" Fresh sparkle replays on every refresh — *low (root cause: FP3)*
Same UUID churn: each `updateLiveItems` re-mints IDs, so `sparklingItemIDs` re-matches
and every < 5-min-old item sparkles again on every Spotlight merge or store change.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB15 🟡 FaviconCache races: concurrent same-host fetches lose, and one network blip pins the globe for the session — *low*
`claim()` marks a host "tried" *before* fetching (`Common/FaviconCache.swift:57`), so
a second item for the same host racing the first gets `.skip` → `nil` and keeps the
generic globe; and a transient network failure also permanently (per session) marks
the host tried. **Fix:** deduplicate via a per-host in-flight `Task` that late callers
await, and only pin *definitive* failures (HTTP non-200 / undecodable image), not
thrown transport errors.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB16 🟡 Checkbox toggle mangles notes with CRLF / Unicode line separators — *low*
`MarkdownText.togglingCheckbox` splits on `CharacterSet.newlines` and rejoins with
`"\n"` (`Common/MarkdownText.swift:117`): pasted CRLF text gains a phantom blank line
per line-ending on the first checkbox tap (`"a\r\nb"` → `["a","","b"]` → `"a\n\nb"`),
and U+2028/29 are silently rewritten. **Fix:** normalize line endings once in a shared
`lines()` helper used by both the renderer and the toggler, so indexes always agree.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB17 🟡 A folder drawer with no (or a broken) directory still advertises a copy drop — then swallows it — *low*
`DrawerHostingView.droppableModel` (`DrawerWindowController.swift:45`) accepts drops
for any folder tab; `handleFileDrop`'s folder branch then bails silently when
`resolveFolder` fails. The user sees a valid green + drop cursor and the files go
nowhere. **Fix:** don't advertise the drop when `model.folderURL == nil`.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB18 🟡 A failed Undo looks exactly like a successful one — *low, needs a design call*
`FileMover.undo`'s return value is ignored (`TabController.swift:1025`); if a file
can't be moved back (renamed/locked/moved-again), the toast dismisses as if all was
well. Needs a small "Couldn't put N item(s) back" presentation — documented here
rather than patched blind since it wants a UI decision.

### FB19 🟡 Importing a layout can silently never persist — *low*
If the on-disk document came from a newer MacDring, `saveNow` (correctly) refuses to
write — but `importData` (`Store/TabStore.swift:212`) still reports success after
replacing the tabs, leaving `document.version` at the newer value, so the *imported*
layout also never saves. **Fix:** adopt the imported document's version on import.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB20 🟡 "You're up to date" when the version couldn't even be parsed — *low*
`UpdateChecker.performCheck` (`Updates/UpdateChecker.swift:141`): an unparseable
release tag or bundle version falls into the "up to date" alert on a user-initiated
check. Honest answer: "couldn't understand the version info."
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB21 🟡 New Tab dialog leaks a previously chosen folder into non-folder tabs — *low*
Pick *Folder*, choose a directory (name auto-fills), then switch Type to *Notes* and
create: the notes tab silently carries `folderBookmark`/`folderURL` and the folder's
name (`Settings/NewTabView.swift:92`). **Fix:** drop the folder fields when the
created kind isn't `.folder`.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB22 🟡 Per-tab grid steppers max out below what the model (and the General pane) allow — *low*
`TabEditor` clamps Columns/Rows to 1…10 / 1…12 (`Settings/TabsView.swift:223`) while
Preferences and the General pane allow 1…12 / 1…16 — a tab created at 16 rows can be
stepped down but never back up. **Fix:** align the ranges.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB23 ⚪ Any cloud provider with "drive" in its name gets branded as Google Drive — *polish*
`CloudLister.providerIconStyle` matches `n.contains("google") || n.contains("drive")`
(`Store/CloudLister.swift:56`) — "Proton Drive" and "pCloud Drive" get Google's green
triangle. "Google Drive" already contains "google"; drop the bare `"drive"` match.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FB24 ⚪ Monogram glyphs: Settings accepts 3 characters, the pill renders 2 — *polish*
`TabsView.monogramBinding` caps at `prefix(3)`; `TabStripView.glyphView` draws
`prefix(2)`. Type "ABC", get "AB". Align the caps.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

---

## 2. Performance

### FP1 🔴 `ItemView`'s ".task" I/O all runs on the main thread — a 300-item drawer ≈ 1,000 main-thread filesystem calls per open — *high*
SwiftUI's `.task` inherits the view's MainActor context, so *everything* in it —
`resolveIcon` (bookmark resolve + `NSWorkspace` icon decode), `isBroken` (second
resolve), `appBundleID` (third resolve + Info.plist read), `resolveMetadata` (fourth
resolve + stat, list mode), and `TrashInspector.trashCount()` (a getattrlist sweep of
every mounted volume) — executes on the main thread, merely deferred
(`Drawer/ItemView.swift:110–130`). The G11 fix moved I/O out of `body`, not off the
main thread, and the delight batch added *more* work to the same task. One item whose
bookmark points at an unreachable network volume can hang the UI for seconds
(`BookmarkResolver.resolve` runs without `.withoutUI`/`.withoutMounting` — known, but
it now runs on-main × N). **Fix:** hop the resolution through `Task.detached` and
assign the `@State` results back on the main actor.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FP2 🔴 One Trash filesystem event re-runs disk I/O for *every* item in the open drawer — *high*
The Trash watch bumps `drawer.model.iconNonce` straight from its kqueue handler with
no coalescing (`TabController.swift:1140`), and `iconNonce` participates in **every**
`ItemView`'s `.task` id. Finder trashing a batch of 50 files = a stream of events ×
every visible item × 3–4 filesystem ops (on the main actor, per FP1) — the nonce
exists only for the Trash item's full/empty icon and badge, yet it invalidates the
whole drawer. **Fix:** debounce the watch like the folder watch already does, and
scope the nonce to trash-kind items in `ResolveKey`.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FP3 🟠 Transient items get fresh UUIDs on every listing — defeating icon caching, SwiftUI diffing, and any state keyed by item ID — *medium*
Every live listing (folder / disks / network / cloud / recents / fresh) rebuilds its
`DrawerItem`s with brand-new `UUID()`s (`Model/DrawerItem.swift:172` and each lister).
Consequences: every refresh re-runs every item's `.task` resolution (the id changed),
SwiftUI treats the whole list as new rows, the Fresh sparkle replays (FB14), and the
Eject-All spinners detach (FB13). **Fix:** derive stable IDs from the item's path +
kind (deterministic UUID), so refreshes preserve identity.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FP4 🟠 The Fresh pill-dot rescans the landing zones on every reconcile — one sweep per keystroke — *medium*
`reconcile()` ends in `updateFreshBadgeTimer()` which unconditionally calls
`refreshFreshBadges()` before arming its 60 s timer (`TabController.swift:1104`) — so
the "light 60 s re-scan" actually also runs once per store mutation: a 10-file drop =
10 sweeps; editing a tab title = one sweep per keystroke (TabEditor commits per
keystroke, known B5); dragging an appearance slider = one per debounce tick. Also:
the timer has no tolerance. **Fix:** scan only when the timer fires or a Fresh tab
first appears; set timer tolerance.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FP5 🟠 An open Fresh drawer re-runs two synchronous main-thread scans *and* restarts the Spotlight gather on every store mutation — *medium (extends known G19)*
`refreshOpenDrawer` → `apply` (sync scan #1, main thread) → `updateSpotlightWatch`
(sync scan #2 + `spotlight.start` teardown/restart) on every reconcile
(`TabController.swift:1169`, `DrawerWindowController.swift:325`). Continuous edits
(e.g. typing in the tab editor) can restart the query faster than it gathers — the
Spotlight merge **never lands**. G19 said "scans twice on open"; it's actually twice
per mutation, plus query starvation. **Fix:** covered by the FB1 rework (Spotlight-only
seed, no restart while a gather for the same tab is in flight).
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FP6 🟠 File-drag hover dirty-writes the drawer model on every drag frame — *medium*
`DrawerHostingView.updateDrag` assigns `model.fileDropSlot` and
`model.isDropTargeted` unconditionally per `draggingUpdated` event
(`DrawerWindowController.swift:67`); `@Published` fires `objectWillChange` even for
identical values, so hovering a drag re-invalidates the whole drawer ~60–120×/s —
which re-sorts (list) or linearly re-scans slots (grid) in `body` each time. **Fix:**
equality-guard both writes. (The deeper fix — precomputed sort/section/slot indexes on
`DrawerModel` — is documented for later.)
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FP7 🟡 Every reconcile force-lays-out every pill and dirty-writes five `@Published` properties per pill — *low*
`update(tab:)` assigns title/color/glyph/edge/drops unconditionally and `place(on:)`
calls `layoutSubtreeIfNeeded()` + `fittingSize` per pill per reconcile
(`Tabs/TabWindowController.swift:159–194`). A 10-file drop (10 mutations, no
batching — known) × 12 tabs = 120 forced SwiftUI layout passes + 600 spurious
publishes. **Fix:** equality-guard the model writes (all `Equatable`); consider a
measured-size cache later.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FP8 🟡 The notes preview re-parses the whole note on every unrelated drawer invalidation — *low*
`MarkdownText.body` re-classifies and re-runs `AttributedString(markdown:)` per line
in a non-lazy `VStack` (`Common/MarkdownText.swift:16`), and the shared `DrawerModel`
invalidates on app launches/quits (`runningBundleIDs`), Trash events (`iconNonce`),
and toast changes. A 1,000-line note re-parses 1,000 times per unrelated event.
**Fix sketch:** cache `[(Line, AttributedString?)]` per text value; `LazyVStack`.
*(Documented — worth doing together with a notes-model refactor, not as a blind patch.)*

### FP9 🟡 FaviconCache hoards full-size images forever — *low*
`images: [String: NSImage]` is unbounded and stores whatever the server returned —
multi-rep ICOs and oversized PNGs — for the whole session of a permanently-running
agent, rendered at 16–64 pt (`Common/FaviconCache.swift:15`). **Fix:** cap + downscale
on store (ImageIO thumbnail), evict oldest.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FP10 ⚪ Misc energy nits — *polish*
`freshBadgeTimer` has no tolerance (fixed with FP4); `updateLiveItems`' direct
`setFrame` during an in-flight open animation extends known B11 to the drawer panel
(needs device observation — documented).

---

## 3. Visual & layout

### FV1 🟠 Modern pill text is hardcoded white — unreadable on light tab colors
`TabStripView.modernTab` uses `.foregroundStyle(.white)` (`Tabs/TabStripView.swift:86`)
over the tab color at 0.62–0.88 opacity. A yellow, mint, or white tab has white text
on a light pill. The classic style already solves this with
`Color.readableForeground` (`Model/ColorHex.swift:62`) — the modern pill should use
the same (and keep its shadow only for the white case).
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FV2 🟠 Drawer chrome is tuned for dark backgrounds and washes out in light mode
Hardcoded white overlays — search-bar fill `.white.opacity(0.10)`
(`DrawerView.swift:123`), undo-banner fill (`:217`), drop-highlight fills
`.white.opacity(0.16)` (`:326`, `:345`), drawer outline `.white.opacity(0.12)`
(`:68`) — are nearly invisible over a light appearance with Frosted/Solid
translucency. **Fix:** semantic colors (`Color.primary.opacity(…)`, separator color)
that adapt to appearance.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FV3 🟡 The undo banner squeezes the exact-fit drawer
`DrawerMetrics.contentSize` budgets for the search bar but not the toast
(`Drawer/DrawerMetrics.swift:97`), so while the banner shows, the last grid row gets
pushed under the fold of the fixed-height drawer. Needs either height budgeting +
re-frame on toast changes, or an overlay presentation. *(Documented — wants a design
pick and an on-device look.)*

### FV4 🟡 The undo banner's transition never animates
`undoBanner` declares `.transition(.move + .opacity)` (`DrawerView.swift:218`) but
`undoToast` is set outside `withAnimation`, so the banner pops. **Fix:** wrap the
set/clear in `withAnimation`.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FV5 ⚪ Time buckets go stale across midnight
`TimeBucket.grouped(…, now: Date())` is evaluated in `body` (`DrawerView.swift:302`);
a Recents drawer left open across midnight keeps "Today" until something re-renders.
*(Polish; documented.)*

---

## 4. UX

### FU1 🟠 Type-to-find keyboard selection can walk below the fold
Arrowing through filtered results moves `selectedItemID` but nothing scrolls the list
(`DrawerView.swift:133`) — the selection disappears off-screen in a long result list.
**Fix:** `ScrollViewReader` + scroll-to-selection.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FU2 🟠 The menu-bar menu can't reach any existing tab
The status menu offers eight "New … Tab" items but no way to *open* a drawer — the
only entry points are the pills themselves. If every tab is auto-hidden (or on a
disconnected display under the park policy), there's no mouse path to your stuff.
**Fix:** a "Tabs" section listing each tab (with its color dot); click = toggle its
drawer.
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FU3 🟠 "Empty the Trash?" doesn't say how many items
Finder's equivalent tells you what you're about to erase; MacDring has
`TrashInspector.trashCount()` one call away (`TabController.swift:938`).
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FU4 🟡 The Recents empty-state copy is wrong for system-sourced tabs
"Nothing opened from MacDring yet." shows for `system`/`both` tabs too
(`DrawerView.swift:491`) — including during the seconds Spotlight is still gathering
(that loading-state gap is known G18; the copy itself is fixable now).
**Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).

### FU5 ⚪ Eight top-level "New X Tab…" menu items
A "New Tab" submenu would halve the menu's height. *(Taste — documented.)*

---

## 5. Missing features
*(Cross-checked against `awesome.md §4` and `ANALYSIS.md §2` — these are gaps not
already on those lists, or with a materially better angle.)*

- **FF1 — Move items between tabs.** There is no way to get an item from tab A to
  tab B short of delete + re-add. Even once drag-*out* ships (known backlog), a drop
  on another pill would add a *copy*. A "Move to Tab ▸" context submenu is the cheap
  80%.
- **FF2 — Separators / labels in the grid.** Still absent (`ANALYSIS §2` calls it
  small). A non-launchable divider item kind fits the existing slot model.
- **FF3 — Global "reveal/hide all tabs" hotkey.** Classic DragThing had a global
  dock-toggle key. With auto-hide tabs, one panic key that reveals everything is the
  safety net (per-tab hotkeys exist; a global one doesn't).
- **FF4 — Disk info on the Disks tab.** DragThing showed volumes' free space.
  `volumeAvailableCapacityKey` is one `resourceValues` call away; the list layout's
  Size column is even `nil` for volumes today. Show "231 GB free" (and see FI5).
- **FF5 — Per-tab icon size.** Icon size is global; a dense Apps grid and a sparse
  folder tab want different sizes. A per-tab override with "use global" default fits
  the existing `BehaviorMode` pattern.
- **FF6 — Bare function-key hotkeys.** Already on the backlog; FB3's fix implements
  the validation half (F1–F20 accepted without modifiers).
  **Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).
- **FF7 — Quick Look.** Reaffirming the backlog item: Space-to-peek is the single
  most-missed file-browser affordance in every drawer type.

---

## 6. Ideas (new — none duplicate `awesome.md §5`)

- **FI1 — Menu-bar drop Inbox.** Drag files onto the *menu-bar icon* to file them
  into a designated tab. The status item's button is an `NSView` —
  `registerForDraggedTypes` works. It's the one drop target that's visible even when
  every tab is hidden.
- **FI2 — A Welcome note that teaches with checkboxes.** First run seeds a "Welcome"
  notes tab whose content is a `- [ ]` checklist of five things to try (drag a file
  onto the pill, type to filter, ⌘-click to reveal, right-click → Customize Icon,
  auto-hide). The checklist renders as real, tappable checkboxes — onboarding that
  demos the notes feature while it teaches the rest.
  **Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).
- **FI3 — Anticipatory pill "breathe."** While a file drag hovers a pill waiting for
  spring-open, scale the pill 1.00→1.04 and back — "keep holding, something's about
  to happen." Pairs with the backlogged countdown glow.
- **FI4 — Tabs that adopt their folder's Finder tag color.** Creating a Folder tab
  for a red-tagged project suggests a red tab (`.tagNames`/label color — no
  permission). The dock inherits your project's color language automatically.
- **FI5 — Volume capacity gauges.** Disks drawer rows get a slim used/free gauge
  behind the Size column; grid icons get a tooltip ("231 GB free of 1 TB"). The
  DragThing disk-dock feel, modernized. (Data: FF4.)
- **FI6 — Poof on remove.** The classic poof already plays for drop-on-Trash; play
  the same `NSAnimationEffect.poof` when an item is removed via its context menu.
  Consistent physicality, three lines.
  **Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).
- **FI7 — Spring-open haptic.** The drag-snap alignment tick exists; add a
  `.levelChange` tick the moment a spring-loaded drawer actually opens under a drag.
  **Status:** 🔧 selected for implementation — see §7 (this line is updated with the PR link once it's open).
- **FI8 — Universal search.** One global hotkey → a small centered field that
  type-to-finds across *all* tabs' items (the per-drawer `DrawerSearch` already has
  the ranking logic), Return launches. "Spotlight for your drawers." Bigger project,
  huge payoff.
- **FI9 — Drag a tab out as a file.** Drag a pill into Finder → writes
  `TabName.macdringtab` (single-tab JSON export); drop such a file back on the app to
  add the tab. Shareable, backupable docks — a genuinely novel trick for this
  category.
- **FI10 — ⌘-scroll to resize icons.** ⌘-scroll over an open drawer live-adjusts
  that tab's icon size (with FF5's per-tab override as the backing store) —
  Finder-style direct manipulation instead of a Settings slider.

---

## 7. Implementation plan

Selected for implementation, each on its own branch/PR — grouped only where two items
edit the same lines of code (separate PRs there would guarantee conflicts):

| Branch | Covers |
|---|---|
| `claude/fb1-fresh-no-tcc` | FB1 + FP4 + FP5 |
| `claude/fb2-stable-restore` | FB2 |
| `claude/fb3-hotkey-validation` | FB3 (+ ships FF6) |
| `claude/fb4-recents-lenient-decode` | FB4 |
| `claude/fb5-itemview-task` | FB5 + FP1 + FP2's nonce scoping |
| `claude/fb6-undo-toast-scope` | FB6 + FV4 |
| `claude/fb7-store-fixes` | FB7 + FB19 |
| `claude/fb8-peek-gating` | FB8 |
| `claude/fb9-drop-slot-consistency` | FB9 |
| `claude/fb10-pill-drop-honesty` | FB10 |
| `claude/fb11-modal-levels` | FB11 + FU3 |
| `claude/fb15-favicon-cache` | FB15 + FP9 |
| `claude/fb16-markdown-line-endings` | FB16 |
| `claude/fb17-drag-hover-guards` | FB17 + FP6 |
| `claude/fb20-update-check-honesty` | FB20 |
| `claude/fb21-newtab-dialog-fixes` | FB21 + FB22 |
| `claude/fb23-cloud-branding` | FB23 |
| `claude/fv1-pill-contrast` | FV1 + FB24 |
| `claude/fp2-trash-watch-debounce` | FP2's debounce half |
| `claude/fp3-stable-transient-ids` | FP3 (fixes FB13 + FB14) |
| `claude/fp7-pill-update-guards` | FP7 |
| `claude/fv2-drawer-chrome` | FV2 + FU1 + FU4 |
| `claude/fu2-menu-tab-access` | FU2 |
| `claude/fi-delight-batch` | FI2 + FI6 + FI7 |

Documented for a later pass (needs device time, a design call, or a bigger refactor):
FB12, FB18, FP8, FP10, FV3, FV5, FU5, FF1–FF5, FF7, FI1, FI3–FI5, FI8–FI10.
