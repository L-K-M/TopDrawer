# MacDring: Sol Review

Reviewed at `main` commit `512bff0` on 2026-07-10. This is a static review of the
complete application, tests, workflows, existing analysis documents, and current
screenshot. The Linux review environment cannot run AppKit, `xcodebuild`, VoiceOver,
or real multi-display tests, so window, focus, animation, Spaces, and visual findings
that need a Mac are explicitly marked **Device verify** rather than presented as
runtime facts.

Severity: **P0** data loss, **P1** major correctness/security/accessibility,
**P2** robustness/performance/UX, **P3** polish. Disposition:

- **Implement** means the defect is confirmed, the desired behavior is unambiguous,
  and the change is suitable for an isolated branch and PR now.
- **Design first** means the problem is real but the correct product behavior needs a
  decision or a broader model/UI design.
- **Device verify** means static evidence is strong but the fix should be validated on
  macOS hardware before it is changed.
- **Backlog** means worthwhile, but lower leverage than the selected work.

## 1. Executive Assessment

MacDring is much better than its current `ANALYSIS.md` suggests in some areas and less
finished than that document claims in others. It has a sound native architecture,
clear product character, unusually strong pure-logic coverage, and thoughtful details
such as stable transient IDs, spring-loaded drops, groups, classic styling, haptics,
Fresh indicators, generated icons, notes checklists, and a menu route back to tabs.
It is not generic launcher boilerplate.

The main release-quality gap is **identity and state ownership across components**.
The app recently gained groups and more asynchronous/live behavior, but several paths
still assume that every item is top-level, every displayed slot identifies one global
item, every query is identified by a tab ID, and a Settings snapshot remains current.
Those assumptions create the highest-severity defects in this review.

The other systemic weakness is **blocking filesystem work on the main thread**.
Cell icon work was moved off-main, but folder enumeration, file moves, trashing,
single-volume eject, bookmark deduplication, and some Settings icon work can still
stall the UI. Fixing this well needs operation state, cancellation, and error UI, not
just scattering detached tasks.

The screenshot shows an appealing, recognizable product, but also a visual hierarchy
problem: the drawers are large dark slabs with much more empty visual mass than their
contents need, header controls are faint and small, and the colored tab can read as a
separate sticker rather than the handle of the same physical object. The best next
visual pass is density, hierarchy, and join quality, not more decoration.

### What Is Already Strong

- Stable screen UUID plus fractional edge anchors are the right foundation.
- `EdgeLayout`, `DrawerMetrics`, grouping transforms, Codable models, listers, and
  preferences have useful unit coverage.
- The AppKit/SwiftUI split is appropriate: AppKit owns panel behavior and external
  drag routing; SwiftUI owns content.
- Tabs and drawers use nonactivating panels and the required all-Spaces/fullscreen
  collection behavior.
- There is no prohibited global key monitor or event tap.
- Lazy grids, one shared drawer, stable IDs for live items, icon caching, debounced
  watches, and guarded pill publishes show active performance work.
- The classic mode, poof, haptics, Welcome checklist, Fresh sparkle, and folder-like
  groups give the app personality without turning it into a theme demo.
- Existing docs explain several non-obvious implementation choices well.

## 2. Confirmed Bugs and Integrity Risks

### SOL-B01 P0: Settings can overwrite newer tab contents with a stale whole-tab draft

**Implemented:** [PR #86](https://github.com/L-K-M/MacDring/pull/86).

`TabEditor` stores a complete `Tab` in `@State` and commits that entire copy on every
change (`MacDring/Settings/TabsView.swift:163-169,348`). A drop, notes edit, icon
change, bookmark repair, or position change can update `TabStore` while Settings is
open. The editor does not receive that update; its next keystroke writes stale items,
notes, icon data, folder data, or anchors back through `updateTab`
(`MacDring/Store/TabStore.swift:134-145`). This is an ordinary data-loss path.

Replace whole-object commits with field-specific bindings/mutations against the latest
store value. Item additions/removals must use item-level operations, not replace a
stale array. Add a store-level regression test proving an unrelated concurrent field
survives a Settings-style edit.

### SOL-B02 P0: Semantically corrupt primary data can bypass recovery and destroy the good backup

**Implemented for the all-records-dropped case:** [PR #87](https://github.com/L-K-M/MacDring/pull/87). Partial-loss diagnostics remain a design item.

`LauncherDocument` deliberately drops unreadable tabs (`LauncherDocument.swift:17-25`).
If the raw JSON has a nonempty `tabs` array but every tab is unreadable, decoding still
succeeds as an empty document. `TabStore` therefore does not try the valid backup
(`TabStore.swift:42-65`). A later save writes the empty document and rotates the bad
primary over the only good backup (`TabStore.swift:447-457`). Import has the same
semantic-validation gap.

Treat a nonempty raw `tabs` array that produces zero valid tabs as a failed primary,
quarantine it, and recover the backup. Reject that shape on import. Longer term,
decoding should return dropped-record diagnostics, preserve partially lossy originals,
and require acknowledgement before rewriting them.

### SOL-B03 P1: Persisted integers can overflow geometry or allocate enormous grids

**Implemented:** [PR #88](https://github.com/L-K-M/MacDring/pull/88).

`gridColumns` and `gridRows` have only lower bounds (`Tab.swift:113-114`), while item
slots and anchor orders are unbounded (`DrawerItem.swift:88`, `ScreenAnchor.swift:36`).
`Int.max` columns can create an enormous `GridItem` array; a huge slot can overflow
row/range multiplication; `Int.max` order can overflow `topOrder() + 1`
(`DrawerView.swift:357-360`, `DrawerMetrics.swift:55-59`,
`TabController.swift:718-723`). A damaged or hand-edited import can crash or exhaust
memory when opened.

Apply the documented UI limits to columns/rows during initialization and decode,
convert implausible slots to unassigned before normalization, and bound order values.
Keep geometry calculations defensive. Add hostile-value decoding and layout tests.

### SOL-B04 P1: Group children do not have the same persistence and mutation guarantees as top-level items

**Implemented:** [PR #85](https://github.com/L-K-M/MacDring/pull/85).

The newly shipped group feature exposed several one-level assumptions:

- `children` decodes strictly as `[DrawerItem]`; one malformed child drops the entire
  group and all valid siblings (`DrawerItem.swift:78-90`).
- `removeItem` and `updateItem` search only top-level items, although child context
  menus expose Rename, Remove, Change Icon, Reset Icon, and Customize Icon
  (`TabStore.swift:288-303`, `DrawerView.swift:557-590`). Those actions silently fail.
- stale bookmark repair traverses only top-level items and writes asynchronous results
  without checking whether the user changed the bookmark meanwhile
  (`TabStore.swift:175-208`). A slow old bookmark can overwrite a newer choice.

Decode children through `FailableDrawerItem`, add shared one-level recursive item
update/removal traversal, dissolve groups that shrink below two children, traverse
children during bookmark repair, and apply repaired bookmarks only if the current
value still equals the snapshotted original. Cover every child action and malformed
child in tests.

### SOL-B05 P1: External drops can act on the wrong item in a group or search result

**Implemented:** [PR #91](https://github.com/L-K-M/MacDring/pull/91).

The AppKit drag destination reports only an integer slot
(`DrawerWindowController.swift:19-35,96-105`). Slots are local to a context: top-level
items, every group, and flattened search results can all have slot 0. The controller
then resolves that slot against top-level `tab.items` (`TabController.swift:770-790`).
A file visibly dropped on a grouped child app/folder can therefore open with, move to,
or trash through an unrelated top-level item sharing its slot.

Use an identity-bearing external target: occupied cells report an item UUID; empty
cells report a slot; background reports neither. Resolve IDs from the actually
displayed context, including group children and flattened search results. Keep slots
only for empty-cell placement. This needs focused model tests and on-device drag tests.

### SOL-B06 P1: A newer-version document remains editable although no change can save

**Disposition: Design first.**

Future-version documents load best-effort and every mutation remains enabled, but
`saveNow` refuses every write (`TabStore.swift:43-45,416-445`). The session appears to
work and all changes disappear at restart. Protecting newer data is correct; accepting
ephemeral edits is not.

Publish a read-only `StoreHealth` state, disable mutations, explain that the layout was
created by a newer version, and offer export/replacement actions. This should be built
with the broader persistence-health UI in SOL-U02.

### SOL-B07 P1: Hover-open can redirect typing away from the foreground app

**Disposition: Design first and device verify.**

Every drawer calls `makeKey`, and searchable drawers immediately focus their field
(`DrawerWindowController.swift:181-208`, `DrawerView.swift:120-143`). A
nonactivating panel can become key without making MacDring frontmost. In hover mode,
merely crossing a tab while typing can therefore redirect input into the drawer. This
contradicts the practical meaning of “never steals focus,” even if application
activation does not change.

Carry an open reason (`click`, `hotkey`, `hover`, `springLoad`). Hover and spring-load
opens should remain pointer-only; key/focus search only after explicit keyboard intent
or a click into the search field. Immediate type-to-find and strict focus preservation
cannot both happen from a passive hover without a prohibited global key monitor.

### SOL-B08 P1: Cross-machine imports can park every imported tab

**Disposition: Design first.**

README promises layouts can be moved between Macs (`README.md:53-56`), and PLAN says
an unknown UUID falls back to the main display (`PLAN.md:328-337`). Reconcile instead
treats any unknown UUID as a disconnected display; the default `.park` policy hides it
(`TabController.swift:158-167,391-398`). The status-menu row then calls the same path
and silently fails to open the drawer.

Import should offer display mapping, with a clear “map unknown displays to this Mac’s
main display” default. Same-machine restore and portable import are different intents
and should not share an implicit policy.

### SOL-B09 P1: Failed launches are recorded as successful and dismiss the drawer

**Implemented:** [PR #90](https://github.com/L-K-M/MacDring/pull/90).

`ItemLauncher.launch` returns failure for unresolved targets or a failed synchronous
open, but `TabController` ignores it, records a Recent, and closes the drawer
(`ItemLauncher.swift:8-28`, `TabController.swift:971-989`). Application errors arrive
asynchronously after the method has already returned success.

Make launch completion-based, record Recents only after confirmed success, and close
only then. Keep the drawer open on failure; the later operation-feedback design can add
an accessible error banner.

### SOL-B10 P2: A duplicate hotkey never retries when the owning MacDring tab releases it

**Implemented:** [PR #93](https://github.com/L-K-M/MacDring/pull/93).

Failed registrations are cached indefinitely (`TabController.swift:866-893`). If tab
B fails because tab A owns the same combination, deleting or changing A clears only
A’s cache. B remains inactive until its own spec changes or the app restarts.

Track failures known to be blocked by another MacDring registration and retry them
after that owner releases the spec. Continue caching external/system failures to avoid
log spam. Surface registration status in Settings as a later UX step.

### SOL-B11 P2: Recents query reuse ignores source changes and stale completions

**Implemented:** [PR #92](https://github.com/L-K-M/MacDring/pull/92).

Spotlight reuse is keyed only by tab ID, and the completion captures whether
MacDring history was included (`TabController.swift:1298-1327`). Changing an open
Recents tab between System and Both while gathering can apply results using the old
source. Once a query finishes, unrelated reconciles can also restart the same one-shot
query because only `isGathering` suppresses restart.

Key the work by the complete query configuration, retain that key after completion,
and reject completion unless it still matches the open drawer. Restart only when the
tab/configuration actually changes or the drawer is reopened.

### SOL-B12 P2: Custom-icon source precedence and editor close behavior contradict the docs

**Implemented:** [PR #89](https://github.com/L-K-M/MacDring/pull/89).

Choosing an image does not clear `iconStyle` (`TabController.swift:1025-1040`). “Use
Default” in the generated editor clears an image only when the new style is nonnil
(`TabController.swift:1078-1091`). Cancelling or closing the editor does not reopen the
drawer, although `docs/custom-icons.md:21-25,54-56` promises one custom source and a
reopen when editing is done (`IconEditorWindowController.swift:15-25`).

Always clear the opposing source after a successful icon choice, let Use Default clear
both, and invoke a close completion for Save, Cancel, and the window close button so
the originating drawer is restored if it still exists.

### SOL-B13 P2: Top-level Recents corruption is silently overwritten later

**Disposition: Backlog with persistence health.**

Per-record failable decoding is good, but malformed top-level JSON returns an empty
history (`RecentsStore.swift:62-69`). The next successful launch persists that empty
array over the unreadable value. Distinguish missing from unreadable data, preserve a
backup/raw value, cap normalized loaded history, and surface repair/clear explicitly.

### SOL-B14 P2: Passive display/appearance changes can permanently rewrite anchors

**Disposition: Design first and device verify.**

De-overlap persists settled positions during every reconcile
(`TabController.swift:171-244`). The guest-display corruption was fixed, but a
temporary resolution, Dock visible-frame change, tab-thickness change, or label-length
change can still move and persist an anchored tab. Restoring the prior environment may
not restore the prior position, contrary to the stable-restore promise.

Separate the requested persisted anchor from transient collision resolution. Persist
de-overlap after explicit user operations, not passive screen/appearance reconcile.
The existing idempotence rationale is valid, so this needs dedicated resolution
round-trip tests and hands-on behavior review.

### SOL-B15 P2: Exact edge endpoints are lost when a drag is committed

**Implemented:** [PR #94](https://github.com/L-K-M/MacDring/pull/94).

A tab placed at position 0 is clamped flush to an edge, but drag commit converts the
frame center back to a nonzero fraction (`EdgeLayout.swift:23-56,275-285`,
`TabController.swift:663-687`). It looks correct until a resolution increase creates a
gap. Add a frame-aware inverse that maps frames touching the along-edge boundaries to
exactly 0 or 1, and use it for drag and settled-frame persistence.

### SOL-B16 P2: Maximum drawers can push their riding tab or animation off-screen

**Disposition: Device verify before implementation.**

Drawer dimensions reserve only 16 points from the screen boundary
(`DrawerMetrics.swift:28-32,98-99`). The riding tab and 22-point nudge are not part of
that envelope (`EdgeLayout.swift:153-174`). A maximum-depth right drawer can put the
tab beyond the opposite edge; the animation can move the drawer beyond the visible
frame.

Cap perpendicular depth using the drawer, riding-tab thickness, and nudge as one
envelope. Add pure containment tests for all edges before changing live geometry.

### SOL-B17 P2: Export write failures are silent and non-atomic

**Implemented:** [PR #95](https://github.com/L-K-M/MacDring/pull/95).

Layout export uses `try? data.write(to:)` (`TabsView.swift:89-97`). Disk-full,
permission, or I/O failure closes the workflow with no backup and no feedback. Write
atomically and present the actual error. A later persistence-health pass should also
make encoding failure explicit instead of returning `nil`.

### SOL-B18 P2: Trashing only non-file URLs reports success

**Implemented:** [PR #96](https://github.com/L-K-M/MacDring/pull/96).

`FileMover.trash` starts true and skips non-file URLs (`FileMover.swift:63-75`). A
browser link routed to Trash can therefore show success/poof while doing nothing.
Return false when there are no eligible file URLs and test mixed/all-link inputs.

### SOL-B19 P2: Folder watch reuse can stay attached to a deleted vnode

**Disposition: Device verify.**

The directory watch is vnode/file-descriptor based, but reuse is keyed only by path
(`TabController.swift:1189-1200`). If the watched directory is renamed/deleted and a
new directory appears at the same path, the path guard can keep the old vnode. Inspect
event flags and reopen on delete/rename/revoke, retrying if replacement is not ready.

### SOL-B20 P2: Duplicate UUIDs are never validated

**Disposition: Backlog with import validation.**

Duplicate tab IDs collapse window identity and can cause `removeTab` to remove several
records; duplicate item IDs make mutations ambiguous. Validate/repair IDs on load and
reject duplicates during import. Record a diagnostic rather than silently assigning
new IDs when doing so would affect external references.

### SOL-B21 P2: Click-outside misses MacDring’s own windows

**Disposition: Device verify.**

Only a global mouse monitor is installed (`TabController.swift:1374-1397`). Global
monitors do not receive events delivered to MacDring, so Settings/New Tab/status-menu
interactions can leave a popup-level drawer obscuring an ordinary window. Add a
carefully filtered local mouse monitor or explicitly close before ordinary-window
actions; verify that clicks inside the active pill/drawer never dismiss unexpectedly.

### SOL-B22 P2: Drop cursor says Copy while files may be moved or trashed

**Disposition: Design first.**

The destination always returns `.copy` (`DrawerWindowController.swift:65-80`), but
folder targets call `FileManager.moveItem`, and Trash removes the source. Decide and
document Finder-style modifier behavior. The operation badge must depend on the
identity of the hovered target, which becomes practical after SOL-B05.

### SOL-B23 P2: Pending launch-at-login approval is shown as enabled/unknown incorrectly

**Disposition: Device verify.**

`SMAppService.Status.requiresApproval` falls through to `nil`, then potentially stale
defaults (`Preferences.swift:207-215`). Turning the toggle off unregisters only an
exact `.enabled` state (`Preferences.swift:226-247`). Model pending approval explicitly,
offer Open Login Items Settings, and verify transitions on Ventura through current macOS.

### SOL-B24 P2: Parked tabs appear actionable in the status menu but cannot open

**Disposition: Design first.**

The menu is described as the recovery path for disconnected tabs
(`AppDelegate.swift:184-205`), but `openDrawer` rejects a parked tab
(`TabController.swift:341-398`). Mark it as disconnected and offer either “Show
Temporarily on Main Display” without changing its anchor or “Move to Main Display.”

### SOL-B25 P2: Live icon override keys collide for non-file URLs

**Disposition: Backlog.**

Live styles use `URL.path` (`DrawerItem.swift:145-151`,
`TabController.swift:1088-1090`). Different web hosts with the same path collide, and
root links all use `/`. Use standardized file paths for file URLs and absolute strings
for non-file URLs, with a legacy-key migration fallback.

### SOL-B26 P1: The update/release chain downloads weakly selected, unsigned artifacts

**Strict asset selection/size checks implemented:** [PR #98](https://github.com/L-K-M/MacDring/pull/98). Signing remains a separate design/distribution item.

The release workflow deliberately ad-hoc signs an unnotarized app
(`.github/workflows/release.yml:67-122`). The updater selects the first unknown asset
when no DMG/ZIP/PKG exists and verifies only HTTP success
(`GitHubRelease.swift:40-51`, `UpdateDownloader.swift:9-19`). There is no checksum,
signature, expected app-name policy, or size verification.

Stop falling back to arbitrary asset types, require HTTPS, and verify downloaded size
against GitHub metadata. The actual release-grade fix is Developer ID signing,
notarization, stapling, and a signed update feed (for example Sparkle with EdDSA).
Until then, the UI and README should be explicit that this is a convenience download,
not a verified in-place updater.

### SOL-B27 P1: Remote favicons create undisclosed network traffic to arbitrary hosts

**Disposition: Design first.**

Opening a URL drawer contacts every link host for `/favicon.ico`
(`ItemView.swift:159-165`, `FaviconCache.swift:83-96`). This can disclose drawer
contents and contact local/private hosts. Responses are downscaled and cache-bounded,
but `URLSession.data` still buffers an unbounded body. Add a privacy disclosure and a
preference, use short timeouts and bounded streaming, and decide whether private/loopback
destinations are allowed. Automatic update checks also need the same privacy section.

### SOL-B28 P3: Controller teardown is incomplete

**Disposition: Backlog.**

`saveAndTeardown` omits the Trash source and several delayed work items
(`TabController.swift:1443-1463`). Process exit limits impact, but it complicates
controller recreation/tests and can leave file descriptors/callbacks alive. Make
teardown idempotently cancel every monitor, source, timer, observer, query, and work
item; consider a safe `deinit` assertion.

## 3. Performance and Responsiveness

### SOL-P01 P1: Multi-item drops reconcile and re-list once per item

**Implemented:** [PR #97](https://github.com/L-K-M/MacDring/pull/97).

The items path loops over `addItem`, and every call publishes, reconciles all windows,
refreshes the open drawer, and schedules a save; placement triggers another pass
(`TabController.swift:820-835`, `TabStore.swift:243-285,416-429`). Deduplication also
re-resolves existing bookmarks repeatedly.

Add a transactional bulk-add operation that deduplicates all targets, assigns/places
slots once, publishes once, reconciles once, and reports actual IDs. No-op duplicates
should not emit a mutation. Test notification count as well as resulting placement.

### SOL-P02 P2: Group preview icon tasks ignore cancellation

**Stale-assignment guard implemented:** [PR #100](https://github.com/L-K-M/MacDring/pull/100). A bounded resolver remains backlogged.

Each group cell starts detached icon work and assigns the result without the
cancellation check used by ordinary items (`ItemView.swift:124-165`). Rapid drawer
switches can waste I/O and apply a stale preview. Check cancellation before assignment.
Longer term, use a bounded icon-resolution service so opening 300 entries cannot spawn
hundreds of independent blocking tasks that outlive SwiftUI cancellation.

### SOL-P03 P1: File move, Trash, Undo, and single-volume eject block the main thread

**Disposition: Design first.**

Drop callbacks synchronously execute `moveItem`, `trashItem`, and Undo
(`TabController.swift:792-818,1132-1143`); single eject is synchronous too
(`TabController.swift:1105-1112`). Cross-volume/network operations can beachball the
drag session for seconds or minutes.

Use a bounded serial utility queue with operation IDs, progress/busy state,
cancellation where possible, partial-result reporting, and main-actor UI updates. Do
not merely detach and lose ownership of operations.

### SOL-P04 P1: Folder opening enumerates, stats, and sorts the whole directory on-main

**Disposition: Design first.**

The 300-item cap limits output, not work: `FolderLister` loads every URL, stats every
entry, sorts all entries, then prefixes (`FolderLister.swift:36-54`). `apply` calls it
synchronously while opening/refreshing (`DrawerWindowController.swift:293-368`). A
large, network, or sleeping-volume folder can freeze presentation, and unrelated
reconciles can repeat it.

Gather off-main with a generation token and explicit loading/error states. Use a
bounded top-N strategy that preserves folders-first plus the selected sort. Apply only
if the same tab/path/configuration remains open.

### SOL-P05 P2: Settings resolves item icons synchronously during row construction

**Disposition: Backlog with Settings redesign.**

`TabsView` calls `ItemView.resolveIcon` inside `ForEach` body
(`TabsView.swift:261-266`). Broken/network targets can stutter scrolling. Use an async,
cached Settings row model; do this with the planned selectable item manager rather
than duplicating drawer-cell machinery ad hoc.

### SOL-P06 P2: Bookmark resolution can mount or show UI during display/dedup paths

**Disposition: Design first.**

Resolution does not use `.withoutUI`/`.withoutMounting`, including synchronous dedup
paths. A stale network bookmark can block unexpectedly. Define separate policies:
quiet/nonmounting for display, dedup, and background repair; user-initiated resolution
for explicit launch/relink.

### SOL-P07 P3: Notes preview reparses the entire note on unrelated invalidations

**Disposition: Backlog.**

`MarkdownText` classifies and parses every line in a non-lazy stack. Shared drawer
model changes such as running apps, Trash, or toasts can invalidate a long note. Cache
parsed lines by text value and use lazy rendering during a notes-model pass.

### SOL-P08 P3: Spotlight badge scans can overlap and lack timeout/error state

**Disposition: Backlog with live-source state.**

The one-minute badge timer can cancel/restart a gather that takes longer than a minute,
and `SpotlightQuery` has no timeout or failure distinction. Add operation state and
generation ownership with SOL-U03 rather than layering timers onto an unobservable
one-shot query.

## 4. UX, Visual, and Accessibility Review

### SOL-U01 P1: Core tabs and items are not keyboard/VoiceOver-complete controls

**Disposition: Design first, highest-value feature project.**

Tabs/items are gesture surfaces (`TabStripView.swift:29-56`,
`ItemView.swift:71-119`), not a complete navigable control model. Arrow/Return works
only while a nonempty search query is active. Drawers below the search threshold have
no keyboard launch path. Almost no explicit accessibility labels, values, hints, or
actions exist.

Build a real selection model for grid/list/group contexts; support arrows, Home/End,
Return, Space, Delete, and context actions. Add button semantics and announce item
type, broken/running/ejecting state, group count, and tab open state. `Cmd-F` should
reveal/focus search regardless of item count. Validate with VoiceOver and Accessibility
Inspector on device.

### SOL-U02 P1: Persistence health and operation errors are invisible

**Disposition: Design first.**

Save failures, backup recovery, quarantine, future-version read-only mode, folder/list
failures, failed launch/eject/move/undo, and update fallback are mostly logs or empty
states. Publish durable `StoreHealth` and transient `OperationStatus` models. Show a
status-menu badge and accessible in-drawer/Settings banners with Retry, Reveal Data
Folder, Relink, or Open Settings actions. Do not use modal alerts for every background
failure.

### SOL-U03 P1: Live sources collapse loading, empty, unavailable, and failed into one state

**Disposition: Design first.**

Fresh immediately says nothing arrived while Spotlight gathers; query startup failure
also becomes empty. Folder/cloud/network errors generally become empty
(`DrawerView.swift:593-641`, `SpotlightQuery.swift:54-80`,
`FolderLister.swift:36-54`). Use shared idle, loading, content, empty, unavailable, and
failed states with contextual actions: Retry, Choose Folder, Connect to Server, or Open
Spotlight Settings.

### SOL-U04 P1: Destructive layout operations have no confirmation or undo

**Disposition: Design first.**

Tab deletion, group deletion, item removal, and Clear Recents are immediate. Deleting a
group can remove many launchers. Implement document-level undo; until then confirm a
populated tab/group with a count. An accessible Undo banner is preferable to repeated
modal warnings.

### SOL-U05 P2: Add Link closes even when the link is invalid

**Implemented:** [PR #99](https://github.com/L-K-M/MacDring/pull/99).

The Add button is always enabled, `DrawerItem.fromLink` may return nil, and the sheet
closes regardless (`TabsView.swift:484-500`). Validate live, keep the text on failure,
disable Add until valid, and preview the normalized destination if space permits.

### SOL-U06 P2: Settings “+” bypasses the real New Tab flow

**Disposition: Design first.**

Settings creates a generic Items tab directly (`TabsView.swift:125-141`), while the
menu flow supports every type and folder selection. Documentation incorrectly says
Settings `+` creates Recents/Network/Cloud tabs. Route both entry points through one
canonical New Tab flow with a concise description for each type.

### SOL-U07 P2: Settings is not yet a keyboard-first item manager

**Disposition: Backlog with SOL-U01.**

Items have no selection, visible remove/reorder controls, relink, group expansion,
Move to Tab, or keyboard actions. Replace the passive rows with a selectable List/Table
and explicit add/remove/reorder/reveal/relink/move controls.

### SOL-U08 P2: Broken items cannot be repaired

**Disposition: Backlog.**

Broken entries dim and show a tooltip, but PLAN’s Relink action is absent. Add Relink,
seed the picker from the old path, and preserve identity, slot, name, and icon.

### SOL-U09 P2: Long labels and maximum grids can clip or leave the screen

**Disposition: Device verify.**

Tab labels use unbounded fixed sizing (`TabStripView.swift:180-210`), and legal
12-column/128-point settings create a grid wider than a laptop screen while the cells
retain fixed icon sizes. Cap tab length with truncation/full tooltip. Make effective
column count/icon size display-aware or provide horizontal navigation and a footprint
warning/preview.

### SOL-U10 P2: Header controls are too faint/small and insufficiently labelled

**Disposition: Backlog as an accessibility starter PR.**

The screenshot and `DrawerView.swift:181-221` show low-emphasis glyph-only actions
with small hit regions. Give them 24-28 point hit areas, hover/focus backgrounds,
explicit accessibility labels/hints, and clear destructive states. Add a status-item
tooltip/accessibility label (`AppDelegate.swift:87-92`).

### SOL-U11 P2: List layout reserves Date even when the source has no dates

**Disposition: Backlog.**

Every row reserves 96 points for Date (`ItemView.swift:197-213`), compressing names in
Items, Disks, Network, and Cloud drawers while displaying blanks. Make metadata columns
source/data-aware: folders/Recents/Fresh get dates, disks get capacity, ordinary Items
prioritize names.

### SOL-U12 P2: Notes preview hides its Edit affordance

**Disposition: Backlog.**

Click-anywhere is the only way into editing (`DrawerView.swift:274-291`). Add a labelled
Edit header action/shortcut so selection and future links do not conflict with an
undiscoverable whole-surface gesture.

### SOL-U13 P2: Group/search context and counts are misleading

**Disposition: Backlog.**

The header counts top-level entries; a group with ten children reads as one. Search
flattens children without identifying their parent. Show “3 groups, 14 items,” use
current-group counts, and add group/path breadcrumbs to search results.

### SOL-U14 P2: Undo banner steals exact-fit content space

**Disposition: Device verify.**

Metrics reserve search height but not Undo height (`DrawerMetrics.swift:13-15,95-99`,
`DrawerView.swift:63-67`). The last row can be pushed under the fold. Prefer an overlay
or include the banner in live sizing; verify the visual transition.

### SOL-U15 P2: Custom images/favicons can distort in square frames

**Disposition: Backlog.**

Resizable images receive fixed square frames without explicit aspect fitting
(`ItemView.swift:309-319`, `TabsView.swift:261-265`). Use aspect-fit in a square icon
box and downsample imported images.

### SOL-U16 P2: Reduced Motion/contrast handling is incomplete

**Disposition: Device verify.**

Main drawer motion respects Reduce Motion, but selection scrolling, group transitions,
Undo, sparkles, arrival dots, poof, and several small animations do not. Running and
arrival state rely on color alone. Centralize motion policy, provide static variants,
honor Increase Contrast/Differentiate Without Color, and test custom fill contrast.

### SOL-U17 P2: Automatic update discovery can interrupt another app

**Disposition: Design first.**

A background check can activate MacDring and show a modal. Background discovery should
badge the status item or notify nonmodally; reserve a modal for explicit Check Now.
Add determinate progress/cancel and honest download fallback.

### SOL-U18 P3: Main menu and status menu need conventional cleanup

**Disposition: Backlog.**

When Settings makes the app regular, the main menu lacks About, Settings, Services,
Hide, File/Close, Window, and Help (`AppDelegate.swift:51-83`). `Cmd-W` does not have
its normal route. The status menu devotes eight top-level rows to one New Tab dialog.
Install conventional menus and place tab kinds in a New Tab submenu or use one New
Tab command.

### SOL-U19 P3: Visual density and hierarchy need a deliberate second pass

**Disposition: Device design pass.**

From `screenshot.png`:

- Drawer surfaces are much larger/darker than sparse content, making the app feel
  heavier than a quick launcher.
- Header controls and counts fade into the chrome; title and content do not establish a
  strong rhythm.
- The tab-to-drawer seam is visually close but not fully one object: border, tint, and
  elevation differ enough that the pill can read as a sticker behind the drawer.
- Large empty grids need an intentional state: subtle slot rhythm, adaptive compacting,
  or a smaller initial drawer, not undifferentiated empty material.
- The notes surface and item grid use different density/edge treatments; this can be a
  feature, but shared header spacing and control emphasis should unify them.

Recommended direction: reduce default icon/drawer footprint slightly, strengthen the
header action hit regions without making them louder than content, tune the tab/drawer
join as one continuous physical object, and show a restrained slot affordance only
during drag/edit mode. Avoid adding gradients, floating cards, or decorative badges
just to fill space.

### SOL-U20 P3: Empty states need direct recovery actions

**Disposition: Backlog with SOL-U03.**

Items offers no Add Files/Add Link button, missing Folder says to find the gear,
Network has no Connect to Server, and Spotlight failure cannot offer settings. Pair
each state with one primary action and one sentence; drag-and-drop should be the
delightful path, not the only path.

### SOL-U21 P3: Localization and larger-text resilience are not implemented

**Disposition: Backlog unless English-only is an explicit product constraint.**

The project declares English/Base but has no string catalog. AppKit strings, enum
display names, pluralization, fixed utility windows, and fixed metadata columns are all
English-sized. Add a String Catalog, plural inflection, pseudo-localization, RTL
review, and resizable/minimum utility-window layouts before claiming localization.

### SOL-U22 P3: About and README presentation are sparse

**Disposition: Backlog.**

About has no project/release/support/privacy/license links. README screenshot alt text
is only “Screenshot,” and one cropped image does not show Settings, groups, classic
mode, search, or empty/loading states. Add restrained links and a small current gallery
with descriptive alt text.

## 5. Missing Features, Ordered by Product Value

1. **Full drawer keyboard navigation plus Quick Look.** Arrow selection and Space to
   preview are the most Mac-native missing interactions.
2. **Relink broken items.** This closes the bookmark-recovery loop and is already
   promised by PLAN.
3. **Move/Copy to Tab.** A context submenu solves most cross-drawer organization
   without a fragile inter-window drag design.
4. **Multi-select and batch actions.** Launch, reveal, remove, move, or customize
   several items.
5. **Drag persistent Items entries out.** Live-source items already drag out; the main
   launcher should not be the exception.
6. **Universal search.** One optional Carbon hotkey searches every tab with tab/group
   breadcrumbs. This is the highest-payoff “beyond DragThing” project.
7. **Live Fresh/System Recents while open.** Keep Spotlight updates enabled and merge
   arrivals without closing/reopening.
8. **Spring-loaded folder items.** Hover during a drag to expose nested destinations.
9. **Per-tab icon size and Fresh scopes.** Dense app grids and sparse project drawers
   need different scales and landing zones.
10. **Separators, labels, and spacers.** These fit the slot model and DragThing’s
    organizational character.
11. **Duplicate Tab / Shift-drag duplicate.** Fast creation of layout variants.
12. **Named layouts/scenes.** Work, Presentation, Travel, docked, and undocked sets.
13. **Complete undo history.** Tab/group/item deletion, grouping, imports, and placement,
    not only file moves.
14. **Disk capacity.** Free-space text and a subtle capacity gauge make Disks genuinely
    useful rather than another Finder shortcut.
15. **Global reveal/hide-all hotkey.** A safety net when all tabs conceal themselves.

## 6. Delightful and Quirky Ideas

- **Menu-bar Inbox.** Drop a file on the status icon and route it to a designated tab
  or choose a destination from a compact menu.
- **Tear-off tab packages.** Drag a pill to Finder to create a single-tab document;
  drop it back to import. This makes drawers shareable and independently backupable.
- **Command-scroll zoom.** `Cmd`-scroll over a drawer adjusts that tab’s icon size,
  Finder-style, once per-tab sizing exists.
- **Finder-tag inheritance.** A new Folder tab suggests the folder’s Finder label
  color, without silently overriding the user.
- **Parked-tab ghosts.** Disconnected tabs appear dimmed in the status menu with the
  display name and a one-click temporary visit on the main screen.
- **Spring-load progress ring.** A restrained outline shows when a drag-hover will
  open; use a static progress treatment under Reduce Motion.
- **Smart group-name suggestions.** Grouping Xcode, Terminal, and GitHub may suggest
  “Development,” but never rename without confirmation.
- **Frecency mode.** Optional frequency plus recency ranking for a “what I actually
  use” drawer.
- **Display map placement.** A miniature arrangement matching System Settings’ display
  layout makes moving tabs between monitors spatial instead of textual.
- **Classic mechanical feedback.** A tiny bevel press and optional haptic in classic
  mode; no novelty sounds by default.
- **Tab pulse on external change.** A subtle one-shot edge glow when a folder/network
  drawer changes while closed, with Reduce Motion respected.
- **Corner Store.** An optional special tab at a screen corner whose four quadrants
  route drops to favorite drawers. This is weird, useful, and very DragThing.

## 7. Security, Privacy, Build, and Documentation

### Release and privacy

- Developer ID signing/notarization is the largest distribution gap. README currently
  says the app carries the Apple Events entitlement, but the ad-hoc release signature
  does not preserve the target’s entitlement/hardened-runtime story.
- Automatic GitHub checks and per-host favicon requests need a concise privacy section.
  Exported JSON also contains notes, bookmarks, URLs, usernames/paths, and custom-icon
  locations; the export UI/docs should describe it as sensitive and not fully portable.
- CI actions use mutable major tags and Homebrew latest packages. Pin actions by commit
  SHA/tool version where practical, scope `contents: write` to publish only, validate
  release tags, verify codesign strictly, and run `hdiutil verify` on the DMG.
- Test-host detection happens after real Preferences/TabStore/DisplayRegistry objects
  initialize (`AppDelegate.swift:7-26`), so tests can read the developer’s real state.
  Inject test services before construction.

### Documentation drift

- `ANALYSIS.md` says nothing P0-P1 is open and only summarizes PRs through #32; both
  are false. Later truth is fragmented across `awesome.md` and `fable-is-awesome.md`.
- `ANALYSIS.md` C1 still says release uses deprecated `--deep`; current workflow does
  not. Its underlying unsigned/non-hardened concern remains.
- PLAN’s model omits groups; several sections still call implemented features non-goals
  or post-v1; first-run says one tab while code creates Apps plus Welcome; import/export
  and animation status are stale; folder prose is duplicated.
- PLAN promises a visible restore offer and Relink, neither exists.
- README calls Folder tabs read-only although dropping files moves them into the
  directory. It says a starter Apps tab appears but omits Welcome.
- Network/Fresh docs say Settings `+` can create those kinds, but it creates Items only.
- Root and `.github` CI/CD documents disagree, and `scripts/build.sh` depends on an
  external helper not explained in README.
- Source comments still refer to deleted historical analysis IDs. Keep an archived ID
  index if those references remain, or replace them with durable issue/PR links.

`ANALYSIS.md` should become the one canonical forward backlog. Completed work belongs
in git/PR history, but removing every completed ID while source comments still cite it
loses context. Preserve a compact completed-index section with PR links and keep open
findings only in the active sections.

## 8. Testing Gaps

Highest priority automated coverage:

1. Concurrent store mutation survives a Settings field edit.
2. Nonempty raw tabs with zero decodable records recover the backup and cannot replace
   the current layout on import.
3. Partially lossy decode blocks/surfaces destructive rewrite.
4. Extreme columns/rows/slot/order values normalize without overflow/allocation.
5. Malformed group child preserves valid siblings; every grouped-child mutation and
   bookmark repair works; stale repair cannot replace a newer value.
6. External drop identity across top level, open groups, and flattened search results.
7. Failed launch does not record a Recent or close the drawer.
8. Duplicate hotkey conflict followed by owner removal/change.
9. Recents source change while Spotlight gathers; stale completion rejection.
10. Bulk add emits one change and preserves dedup/placement order.
11. Exact 0/1 endpoint persistence across resolution changes.
12. Drawer plus riding tab plus animation nudge stays inside every visible frame.
13. Unknown/oversized update assets are rejected.
14. Duplicate tab/item IDs and portable unknown-display imports.
15. Malformed top-level Recents data is preserved.

Highest priority manual macOS matrix:

- Focus while click-, hotkey-, hover-, and spring-opening from another app’s text field.
- VoiceOver, Accessibility Inspector, keyboard-only grid/list/group/search, Increase
  Contrast, Differentiate Without Color, Reduce Motion, and Reduce Transparency.
- Two-plus displays: shared edges, negative coordinates, Dock edges, resolution/orientation
  changes, disconnect/reconnect, main-display swap, clamshell, Stage Manager.
- Spaces/fullscreen and Floating/Normal levels.
- Huge/network/offline folders; sleeping/ejecting volumes; cloud providers appearing.
- Group/search drops onto apps/folders/Trash; cross-volume moves; partial failures.
- Very long/empty names, 12x16 at 128 points, small laptop visible frames, and larger text.
- Installer artifact: Info.plist/resources/entitlements, code signature, DMG verification,
  minimum macOS launch, update download, and Gatekeeper instructions.

## 9. Name Review

`MacDring` has two problems: it is hard to parse aloud, and it describes lineage more
than the product. The replacement should evoke a physical place at the screen edge,
remain broad enough for notes/disks/files/URLs, and pair with a descriptive subtitle.
Avoid crowded words such as Dock, Shelf, Launcher, Sidekick, and Tuck.

### Ranked shortlist

1. **Drawledge** (`DRAW-ledge`) - a drawer at the screen ledge. Most product-specific,
   memorable, and visually suggestive. Subtitle: “Edge drawers for your Mac.” The pun
   may need one exposure before spelling is obvious.
2. **Brimfold** (`BRIM-fold`) - useful things folded into the screen’s brim. Polished,
   distinctive, and broad; less immediately descriptive.
3. **ScreenSill** - instantly understandable: a place where useful things sit at the
   edge. Less ownable and slightly utilitarian.
4. **Ledgelet** - light, compact, and Mac-utility-like. The diminutive fits a menu-bar
   agent, though it undersells power features.
5. **Railnook** - a concealed personal nook attached to the screen rail. Friendly and
   physical, with low apparent software collision.
6. **Tabstead** - tabs with a stable home; especially apt for sacred placement. “Tab”
   can initially suggest a browser utility.
7. **Drawrail** - drawers travelling from an edge rail. Mechanical and clear, a little
   industrial.
8. **Screenstead** - emphasizes dependable restore and a home for things; longer and
   less playful.
9. **Selvedge** (`SELL-vedge`) - the self-finished edge of fabric. Elegant, distinctive,
   and conceptually perfect for an edge utility, but pronunciation/discoverability and
   existing fashion uses need research.
10. **Corner Store** - delightful and instantly memorable, especially if corner tools
    ever ship. It inaccurately implies corners rather than every edge and is difficult
    to own in search.

### Recommendation

Use **Drawledge** if distinct interaction and character matter most, **Brimfold** if a
clean abstract brand matters most, or **ScreenSill** if immediate comprehension matters
most. My personal choice is **Drawledge: Edge drawers for your Mac**; it preserves the
physicality and quirk of DragThing without sounding like a clone or a temporary code
name.

Preliminary collision checks are not trademark or legal clearance. Before renaming,
check the top three against Apple’s App Store, GitHub, package managers, domains, and
the relevant trademark classes. Avoid the already crowded/colliding Railnest, Tabloom,
Brimlet, Tabinet, Edgeward, Sidefold, SideKeep, Railkeep, Tuckrail, Drawlet, Rimfold,
Taboret, and Sidelatch.

## 10. Selected Implementation Set

Each selected entry was implemented and merged through a separate branch/PR. The
patches keep model/store, drag identity, controller behaviors, UI validation, and
updater changes in their own commits and avoid opportunistic formatting.

| Entry | Pull request | Coverage / follow-up |
|---|---|---|
| SOL-B01 | [#86](https://github.com/L-K-M/MacDring/pull/86) Field-wise Settings edits | Store regression; macOS CI passed |
| SOL-B02 | [#87](https://github.com/L-K-M/MacDring/pull/87) Loss-aware recovery/import | TabStore tests |
| SOL-B03 | [#88](https://github.com/L-K-M/MacDring/pull/88) Persisted layout bounds | Codable/metrics tests |
| SOL-B04 | [#85](https://github.com/L-K-M/MacDring/pull/85) Group integrity | Codable/group/store tests |
| SOL-B05 | [#91](https://github.com/L-K-M/MacDring/pull/91) Identity-bearing drop targets | Model tests + device follow-up |
| SOL-B09 | [#90](https://github.com/L-K-M/MacDring/pull/90) Confirmed launch results | Launcher/session tests; macOS CI passed |
| SOL-B10 | [#93](https://github.com/L-K-M/MacDring/pull/93) Hotkey conflict retry | macOS CI passed; Carbon device follow-up |
| SOL-B11 | [#92](https://github.com/L-K-M/MacDring/pull/92) Keyed Spotlight queries | macOS CI passed; device follow-up |
| SOL-B12 | [#89](https://github.com/L-K-M/MacDring/pull/89) Icon round-trip | Store tests + device window follow-up |
| SOL-B15 | [#94](https://github.com/L-K-M/MacDring/pull/94) Exact edge endpoints | EdgeLayout tests |
| SOL-B17 | [#95](https://github.com/L-K-M/MacDring/pull/95) Export errors | Store test + manual failure path |
| SOL-B18 | [#96](https://github.com/L-K-M/MacDring/pull/96) No-op Trash rejection | FileMover tests |
| SOL-B26 | [#98](https://github.com/L-K-M/MacDring/pull/98) Update asset validation | Release/downloader tests |
| SOL-P01 | [#97](https://github.com/L-K-M/MacDring/pull/97) Batch drop mutation | Notification/placement tests |
| SOL-P02 | [#100](https://github.com/L-K-M/MacDring/pull/100) Group preview cancellation | macOS CI passed; device follow-up |
| SOL-U05 | [#99](https://github.com/L-K-M/MacDring/pull/99) Add Link validation | Model tests; macOS CI passed |

Before merge, every selected PR passed macOS Build & Test on a branch containing #85's
group-test correction. Integration conflicts were resolved against the accumulating
`main` and the affected branches passed CI again.

The remaining entries are intentionally not drive-by implementations. They need a Mac,
a product decision, a reusable operation/status model, or a coherent accessibility and
keyboard design.
