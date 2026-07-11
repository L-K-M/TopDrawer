# Top Drawer: Open Backlog

The canonical, forward-looking backlog for **Top Drawer** (formerly MacDring — the
product rename shipped in July 2026; record in section 7). This file
consolidates and supersedes the earlier review documents `awesome.md`,
`fable-is-awesome.md`, and `sol.md` (deleted 2026-07-11; their full text remains in
git history). Completed work is cleared from the active sections; section 7 keeps a
compact index of finding IDs → merged PRs so source comments and older references do
not lose their context.

Evidence baselines: the fable review read `main` @ `3803678` (2026-07-02); the sol
review read `main` @ `512bff0` (2026-07-10). `file:line` references cite those
snapshots — expect small drift. Code identifiers, the Xcode target/scheme, the
`MacDring/` folder, and the bundle ID intentionally still say MacDring (the rename
record in section 7 lists what stays and why).

Severity: **P0** data loss, **P1** major correctness/security/accessibility,
**P2** robustness/performance/UX, **P3** polish. Labels:

- **Design**: decide the product behavior before implementation.
- **Device**: validate on a real Mac; static review is not sufficient.
- **Project**: a coherent feature/refactor, not a drive-by patch.

Lineage tags like *(was SOL-B07)* connect items to the review that produced them.
macOS CI is the source of truth for compilation and unit tests. Multi-monitor
windowing, focus, Spaces/fullscreen, AppKit drag sessions, Carbon/ServiceManagement,
accessibility, and visual behavior need the manual matrix in section 6.

**Systemic picture** (from the sol review): the architecture is sound — stable screen
UUIDs + fractional anchors, a clean AppKit/SwiftUI split, nonactivating panels, no
prohibited global key monitor, strong pure-logic test coverage, and real product
character. The two systemic weaknesses are (1) **identity and state ownership across
components** — paths that assume every item is top-level, every slot is global, every
query is identified by tab ID, or a Settings snapshot stays current — and (2)
**blocking filesystem work on the main thread**. Fixing the latter well needs
operation state, cancellation, and error UI, not scattered detached tasks.

## 1. Release-Quality Blockers

### A1 P1: Future-version documents accept edits that can never save

*(was SOL-B06)* `TabStore` correctly refuses to rewrite a document from a newer
schema (`TabStore.swift:43-45,416-445`), but all mutations remain enabled. Work
appears to succeed and disappears after restart.

**Action (Design):** publish a read-only `StoreHealth` state, disable mutation, explain
that the document was created by a newer version, and offer export or explicit layout
replacement. Build this with A4 rather than adding isolated alerts. (An early sketch
of the banner idea: load best-effort and explain why saving is disabled.)

### A2 P1: Hover-open can redirect typing from the foreground app

*(was SOL-B07)* Every drawer calls `makeKey`, and searchable drawers immediately
focus their field (`DrawerWindowController.swift:181-208`, `DrawerView.swift:120-143`).
A nonactivating panel can become key without making the app frontmost, so in hover
mode merely crossing a tab while typing elsewhere can redirect subsequent input into
the drawer — contradicting the practical meaning of "never steals focus."

**Action (Design + Device):** carry an open reason (`click`, `hotkey`, `hover`,
`springLoad`). Hover/spring opens remain pointer-only; acquire key/search focus only
after explicit keyboard intent or a click into an input. Verify against another app's
text field and input methods. Immediate type-to-find and strict focus preservation
cannot both happen from a passive hover without a prohibited global key monitor
(AGENTS.md hard constraint) — do not add one.

### A3 P1: Portable imports can park every foreign-display tab

*(was SOL-B08; folds in SOL-B20)* Unknown display UUIDs follow the
disconnected-display policy (`TabController.swift:158-167,391-398`); the default Park
policy hides the imported tabs, and the status-menu row then silently fails to open
them. README promises cross-machine movement (`README.md:53-56`) and PLAN promises a
main-display fallback (`PLAN.md:328-337`).

**Action (Design):** add an import display-mapping step, defaulting unknown UUIDs to
the current main display. Distinguish portable import from same-machine restore —
they are different intents and should not share an implicit policy. Also validate
duplicate tab/item UUIDs (duplicates collapse window identity, make `removeTab`
remove several records, and make mutations ambiguous), maximum counts, and
sensitive/path-bearing content before replacement.

### A4 P1: Persistence health and operation failures are mostly invisible

*(was SOL-U02; folds in SOL-B13 and fable FB18)* Save failures, backup recovery,
quarantine, partial lossy decode, malformed Recents, future-version read-only mode,
failed launch/eject/move/Undo/Empty Trash, and live-source failures are logs, silent
dismissal, or indistinguishable empty states. Concretely: `FileMover.move/trash`,
`DiskEjector.eject`, and `ItemLauncher.open(_:withApp:)` return values callers
ignore; a failed Undo looks exactly like a successful one (`FileMover.undo`'s result
was ignored at `TabController.swift:1025`); malformed top-level Recents JSON decodes
to an empty history that the next launch persists over the unreadable bytes
(`RecentsStore.swift:62-69`).

**Action (Project):** introduce durable `StoreHealth` and transient `OperationStatus`.
Expose a status-item badge and accessible Settings/drawer banners with Retry, Reveal
Data Folder, Relink, or Open Settings actions. Preserve partially lossy originals and
require acknowledgement before rewriting. Distinguish absent Recents data from corrupt
top-level JSON so the next launch does not overwrite recoverable bytes; cap normalized
loaded history and surface repair/clear explicitly.

### A5 P1: Remote favicons make undisclosed requests to arbitrary hosts

*(was SOL-B27)* Opening a link drawer requests `/favicon.ico` from every link host
(`ItemView.swift:159-165`, `FaviconCache.swift:83-96`), revealing drawer contents and
potentially contacting local/private services. Responses are downscaled and
cache-bounded, but `URLSession.data` can still buffer an unbounded body.

**Action (Design):** add a privacy disclosure and preference; choose whether remote
favicons default on. Use short timeouts and bounded streaming, and define policy for
loopback/private destinations. Document automatic GitHub update checks and local
launch history in the same privacy section.

### A6 P1: Distribution/update chain is unsigned and not release-grade

*(was SOL-B26 remainder)* Releases are ad-hoc signed, not Developer ID
signed/notarized/stapled (`.github/workflows/release.yml`). Strict asset selection,
HTTPS, and size verification landed in PR #98, but there is still no cryptographic
update signature or checksum, and README's entitlement wording does not describe the
shipped ad-hoc artifact accurately.

**Action (Project):** Developer ID sign with hardened runtime and entitlements,
notarize, staple, verify with strict `codesign`, and use a signed feed such as Sparkle
EdDSA. Until then, call downloads a convenience and retain honest Gatekeeper/manual
installation copy.

### A7 P1: Core drawers are not keyboard/VoiceOver complete

*(was SOL-U01)* Tabs/items are gesture surfaces rather than a complete
control/selection model (`TabStripView.swift:29-56`, `ItemView.swift:71-119`).
Arrow/Return works only while a nonempty search query is active; drawers below the
search threshold have no keyboard launch path; groups and context actions lack
keyboard routes; explicit accessibility labels/values/actions are sparse.

**Action (Project + Device):** build one selection model for grid/list/group/search.
Support arrows, Home/End, Return, Space, Delete, context actions, and `Cmd-F` regardless
of item count. Announce item type, broken/running/ejecting state, group count, and tab
open state. Validate with VoiceOver and Accessibility Inspector.

### A8 P1: Destructive layout actions have no complete undo/confirmation model

*(was SOL-U04)* Tab deletion, group deletion, item removal, Clear Recents, imports,
and grouping can be irreversible. A group can hide many launchers behind one Delete
Group action.

**Action (Design):** add document-level undo. Until then, confirm populated tab/group
deletion with counts. Prefer an accessible Undo banner over repeated modal alerts.

## 2. Correctness and Runtime Risks

### R1 P2: Passive reconciles can permanently rewrite stable anchors

*(was SOL-B14)* De-overlap persists positions during screen/appearance reconciliation
(`TabController.swift:171-244`). Temporary resolution, Dock visible-frame, label, or
thickness changes can become permanent — restoring the prior environment may not
restore the prior position, contrary to the stable-restore promise. The
guest-display corruption is fixed (PR #62), but anchored-display transient geometry
remains.

**Action (Design + Device):** separate requested persisted anchors from transient
collision resolution. Persist collision settlement after explicit user operations, not
passive environment changes. The existing idempotence rationale is valid, so add
dedicated resolution/Dock/appearance round-trip tests and hands-on review.

### R2 P2: Maximum drawers can push the riding tab/animation off-screen

*(was SOL-B16)* Drawer dimensions reserve only 16 points from the screen boundary
(`DrawerMetrics.swift:28-32,98-99`); the riding tab and the 22-point animation nudge
are not part of that envelope (`EdgeLayout.swift:153-174`). A maximum-depth drawer can
put the tab beyond the opposite edge or animate beyond the visible frame.

**Action (Device):** cap perpendicular depth using one envelope containing drawer,
riding tab, and nudged frame. Add pure containment tests for every edge and small
visible frames before changing live geometry.

### R3 P2: Click-outside misses the app's own windows

*(was SOL-B21 / awesome G13)* Only a global mouse monitor is installed
(`TabController.swift:1374-1397`), and global monitors do not receive same-process
events — so clicking Settings, the New Tab dialog, or the status menu while a drawer
is open can leave a popup-level drawer above ordinary windows.

**Action (Device):** add a carefully filtered local mouse monitor or explicitly close
before ordinary-window actions. Never dismiss clicks inside the active drawer/pill —
the guard is interaction-sensitive and needs on-device verification.

### R4 P2: Drop cursor advertises Copy for Move/Trash operations

*(was SOL-B22 / awesome B10)* The drag destination always returns `.copy`
(`DrawerWindowController.swift:65-80`), but folder targets call
`FileManager.moveItem` (including cross-volume) and Trash removes the source.

**Action (Design):** now that identity targeting has landed (PR #91), choose
target-sensitive operations and Finder modifier semantics: add reference, open-with,
move/copy, and Trash. The badge must vary by hovered slot/tab kind. Report partial
failures and correct README's "read-only folder" language.

### R5 P2: Folder watch can remain attached to a deleted vnode

*(was SOL-B19)* The directory watch is vnode/file-descriptor based, but reuse is
keyed only by path (`TabController.swift:1189-1200`). A replacement folder at the
same path may not refresh.

**Action (Device):** inspect event flags and reopen on delete/rename/revoke, with retry
when a replacement is not ready.

### R6 P2: Parked status-menu rows are enabled but cannot open

*(was SOL-B24)* The menu is described as the hidden-tab recovery route
(`AppDelegate.swift:184-205`), yet parked tabs have no live screen and `openDrawer`
rejects them (`TabController.swift:341-398`).

**Action (Design):** mark the display as disconnected and offer "Show Temporarily on
Main Display" without anchor mutation plus "Move to Main Display."

### R7 P2: Pending Launch at Login approval is misrepresented

*(was SOL-B23 / fable FB12)* `SMAppService.Status.requiresApproval` maps to `nil` and
falls through to stale/unknown stored state (`Preferences.swift:207-215`), so a
registration parked in System Settings → Login Items shows as enabled while it is not
running. Turning the toggle off unregisters only an exact `.enabled` state
(`Preferences.swift:226-247`), so it does not necessarily clear a pending approval.

**Action (Device):** model enabled, disabled, pending approval ("waiting for approval
in System Settings"), unavailable, and error; offer Open Login Items Settings; test
state transitions on supported macOS versions.

### R8 P2: Live icon override keys are path-only

*(was SOL-B25)* Live styles key on `URL.path` (`DrawerItem.swift:145-151`,
`TabController.swift:1088-1090`): different web hosts with the same path collide, and
root links all share `/`.

**Action:** use standardized file paths for file URLs and absolute strings for other
URLs; read legacy path keys as a migration fallback.

### R9 P2: Interrupted tab drags have no fallback cancellation

If a pill disappears during a SwiftUI drag (display disconnect, removal, forced order
out), `.onEnded` may not clear drag state, leaving concealment disabled for that tab.

**Action (Device):** add an AppKit mouse-up/cancel fallback and clear drag state when
reconcile removes or parks the dragged window.

### R10 P2: Direct frame updates can race in-flight animations

*(was awesome B11; extended by fable FP10)* Refresh/live-item frame changes and pill
updates can set frames while an animation has an older target; completion may leave
the riding pill/drawer misaligned until another reconcile. `updateLiveItems`' direct
`setFrame` extends the same race to the drawer panel during an in-flight open
animation.

**Action (Device):** observe rapid open/close/switch, live-list resize, and preference
changes; cancel/reassert animation targets using a generation if reproduced.

### R11 P3: Classic drag preview uses modern sizing assumptions

*(was awesome B17a)* The drag frame has no `.classic` branch, unlike `place`, so the
preview does not mirror classic fitting behavior and may clip transiently.

**Action (Device):** compare classic placement and cross-edge drag preview sizing, then
share the sizing calculation if confirmed.

### R12 P3: Folder-item drops silently discard browser links

*(was awesome B17b)* The folder branch of `handleFileDrop` filters to file URLs (the
app branch keeps links), so a link dropped on a folder *item* vanishes while the
target can still look actionable.

**Action (Design):** choose refusal, add-to-tab fallback, or creation of a `.webloc`;
advertise only the chosen operation.

### R13 P3: Hotkey recorder monitor lifetime needs a backstop

*(was awesome B20 + G16's surfacing half)* Teardown relies solely on SwiftUI
`onDisappear`; a surviving local monitor would swallow every key-down. Separately, the
recorder shows a spec as configured even when macOS rejected the registration (the
retry-after-conflict half shipped in PR #93).

**Action (Device):** verify window/focus lifecycle and add resign/timeout cleanup if
needed. Surface Carbon registration conflict/reserved status in Settings and warn
against common one-modifier editing shortcuts.

### R14 P3: Trash metadata count can include `.DS_Store`

*(was awesome B28 — still cited by `TrashInspector.swift`)* The metadata-only
`ATTR_DIR_ENTRYCOUNT` count includes Finder bookkeeping, so the badge/confirmation can
say full when Finder shows empty. A metadata-only count cannot see entry names.

**Action (Device):** find a permission-safe enumeration/metadata strategy that excludes
Finder bookkeeping **without reintroducing a Trash-access prompt**; validate on a real
volume.

### R15 P3: Teardown omits sources and delayed work

*(was SOL-B28)* `saveAndTeardown` does not cancel the Trash watch and several delayed
work items (`TabController.swift:1443-1463`). Process exit limits impact, but it
complicates controller recreation/tests and can leave descriptors/callbacks alive.

**Action:** make teardown idempotently cancel every monitor, dispatch source, observer,
timer, query, and delayed work item; consider safe `deinit` assertions.

## 3. Performance and Responsiveness

### P1 P1: File move, Trash, Undo, Empty Trash, and single eject block the main thread

*(was SOL-P03; awesome's "main-thread blocking I/O" family)* Drop callbacks
synchronously execute `moveItem`, `trashItem`, and Undo
(`TabController.swift:792-818,1132-1143`); single-volume eject is synchronous too
(`TabController.swift:1105-1112`); Empty Trash executes synchronous `NSAppleScript`
on the main thread (`FileMover.emptyTrash`). Cross-volume/network operations can
beachball the drag session for seconds or minutes.

**Action (Project):** use a bounded serial utility queue with operation IDs,
progress/busy state, cancellation where possible, partial-result reporting, and
main-actor application. Do not detach work without ownership.

### P2 P1: Folder opening enumerates/stats/sorts everything on-main

*(was SOL-P04 / awesome G8)* The 300 cap bounds output, not work: `FolderLister`
loads every URL, stats every entry, sorts all, then prefixes
(`FolderLister.swift:36-54`); `apply` calls it synchronously while opening/refreshing
(`DrawerWindowController.swift:293-368`), and unrelated reconciles can repeat it. A
large, network, or sleeping-volume folder can freeze presentation.

**Action (Project):** gather asynchronously with a generation key and explicit
loading/error state. Use bounded top-N selection preserving folders-first and the
chosen sort. Apply only if tab/path/config still match.

### P3 P2: Settings resolves row icons synchronously

*(was SOL-P05 / awesome G10)* `TabsView` calls `ItemView.resolveIcon` inside the
`ForEach` body (`TabsView.swift:261-266`), so large/networked/broken item lists
stutter Settings scrolling.

**Action:** use an async cached row model during the planned selectable Settings item
manager redesign (U3) rather than duplicating drawer-cell machinery ad hoc.

### P4 P2: Bookmark resolution can mount/show UI in quiet paths

*(was SOL-P06)* Display, deduplication, and background repair use the same resolution
policy as explicit launch — no `.withoutUI`/`.withoutMounting` — so a stale network
bookmark can block or prompt unexpectedly.

**Action (Design):** use quiet `.withoutUI`/`.withoutMounting` policies for display,
dedup, and repair; reserve user-interactive resolution for launch/relink.

### P5 P2: Icon work is unbounded despite cancellation guards

*(was SOL-P02 remainder)* PR #100 prevents stale group-preview assignments, but
hundreds of detached filesystem/icon tasks (`ItemView.swift:124-165`) can still
outlive rapid open/close cycles.

**Action (Project):** centralize icon resolution in a bounded cache/service with
cancellation and request coalescing, so opening 300 entries cannot spawn hundreds of
independent blocking tasks that outlive SwiftUI cancellation.

### P6 P3: Notes preview reparses on unrelated drawer invalidations

*(was SOL-P07 / fable FP8)* `MarkdownText.body` re-classifies and re-runs
`AttributedString(markdown:)` per line in a non-lazy stack (`MarkdownText.swift:16`),
and the shared `DrawerModel` invalidates on app launches/quits (`runningBundleIDs`),
Trash events (`iconNonce`), and toast changes — a 1,000-line note reparses per
unrelated event.

**Action:** cache parsed lines by text value (sketch: `[(Line, AttributedString?)]`)
and use lazy rendering, during a notes-model pass rather than as a blind patch.

### P7 P3: Spotlight work needs timeout/error/live-state ownership

*(was SOL-P08)* Queries have no timeout/failure distinction (`SpotlightQuery`), and
the one-minute badge timer can cancel/restart a gather that takes longer than a
minute.

**Action:** fold query generation, timeout, loading/error state, and live updates into
the live-source state project (U1), not more independent timers.

### P8 P3: Trash/context metadata work can be unexpectedly expensive

*(from awesome's main-thread list)* `TrashInspector` stats every mounted volume while
building a context menu; synchronous bookmark dedup can also touch network targets.

**Action:** cache/coalesce metadata and apply the quiet bookmark policy from P4.

### P9 P3: Settings still reconciles on every field keystroke

*(awesome's mutation-batching remainder — the multi-item drop half shipped in PR #97)*
PR #86 prevents stale whole-tab overwrites, but field bindings still create one store
mutation and full controller reconcile per title/monogram keystroke.

**Action:** coalesce high-frequency Settings text edits or separate persistence publish
from window reconciliation while preserving immediate visual feedback and crash-safe
save behavior.

### P10 P3: Drawer body re-derives sort/section/slot lookups per invalidation

*(fable FP6's documented deeper half — the equality guards shipped in PR #75)* The
drawer body re-sorts (list layout) or linearly re-scans slots (grid) on each
invalidation.

**Action:** precompute sort/section/slot indexes on `DrawerModel` and invalidate them
with the data, not the render pass.

### P11 P3: Pill sizing re-measures on every reconcile

*(fable FP7's documented half — the equality guards shipped in PR #81)* `place(on:)`
still calls `layoutSubtreeIfNeeded()` + `fittingSize` per pill per reconcile
(`TabWindowController.swift:159-194`).

**Action:** add a measured-size cache keyed by the pill's content inputs.

## 4. UX, Visual, and Product Work

### U1 P1: Live sources need loading/empty/unavailable/failed states

*(was SOL-U03 / awesome G18)* Fresh/System Recents, folder, cloud, and network
failures collapse into "empty" (`DrawerView.swift:593-641`,
`SpotlightQuery.swift:54-80`, `FolderLister.swift:36-54`) — a live tab can look empty
while Spotlight is still gathering, and query startup failure also reads as empty.

**Action (Project):** shared `.idle/.loading/.content/.empty/.unavailable/.failed`
state with Retry, Choose Folder, Connect to Server, or Open Spotlight Settings.
Keep Spotlight live while Fresh/System Recents drawers are open. Include a timeout
policy and its UI.

### U2 P2: Settings `+` bypasses the canonical New Tab flow

*(was SOL-U06 / awesome G21 + G22)* Settings creates only a generic Items tab
(`TabsView.swift:125-141`) although the menu flow supports every kind and
documentation promises the same. The New Tab dialog also uses a fixed compact size
that could clip under localization or larger Dynamic Type.

**Action (Design):** route menu and Settings through one New Tab flow with icon, title,
and one-line descriptions. Make utility windows resizable/minimum-sized for larger text
and localization; the looser layout wants on-device visual verification.

### U3 P2: Settings is not a keyboard-first item manager

*(was SOL-U07)* No selection, visible remove/reorder, group expansion, Relink, Move
to Tab, or full keyboard actions.

**Action (Project):** selectable List/Table with add/remove/reorder/reveal/relink/move
controls and async icons (P3). This should share the selection/accessibility work in A7.

### U4 P2: Broken items cannot be relinked

*(was SOL-U08 / awesome G17)* PLAN promises Relink, but the only remedy is
remove/re-add. Broken items dim with a tooltip and nothing else.

**Action:** add a `Relink…` context action wiring an `NSOpenPanel` (seeded from the
old path) through DrawerModel → TabController; preserve item ID, slot, name, and icon
while re-minting the target bookmark/URL. Add a visible/accessible missing-item state.

### U5 P2: Long labels and maximum grids can clip/overflow

*(was SOL-U09)* Tab labels use unbounded fixed sizing (`TabStripView.swift:180-210`).
Legal 12-column/128-point settings can create content wider than a laptop drawer while
cells retain fixed icon sizes.

**Action (Device):** cap tab length with truncation and full tooltip/accessibility text.
Make effective grid columns/icon size display-aware or provide horizontal navigation
and footprint warning/preview.

### U6 P2: Header controls are faint, small, and under-labelled

*(was SOL-U10)* The current screenshot and `DrawerView.swift:181-221` show
low-emphasis glyph-only actions with small hit regions.

**Action:** 24-28 point hit areas, hover/focus backgrounds, labels/hints, clear
destructive states, and a status-item tooltip/accessibility label
(`AppDelegate.swift:87-92`). Suitable as an accessibility starter PR ahead of A7.

### U7 P2: List columns are not source/data aware

*(was SOL-U11)* Every row reserves 96 points for Date (`ItemView.swift:197-213`) even
for Items, Disks, Network, and Cloud rows with no date, compressing names to show
blanks.

**Action:** dates for Folder/Recents/Fresh, capacity for Disks, and name-first ordinary
Items. Add capacity/free-space metadata (`volumeAvailableCapacityKey` is one
`resourceValues` call) and an optional subtle volume gauge — see roadmap item 14.

### U8 P2: Notes preview hides Edit

*(was SOL-U12)* Click-anywhere is the sole editing affordance
(`DrawerView.swift:274-291`) and conflicts with selection/future links.

**Action:** labelled Edit header action and shortcut; retain whole-surface click only as
a convenience.

### U9 P2: Group/search context and counts are misleading

*(was SOL-U13)* Header count is top-level only (a group with ten children reads as
one); flattened child search results have no parent breadcrumb.

**Action:** show group/item totals ("3 groups, 14 items"), current-group count, and
parent/path subtitles in search results.

### U10 P2: Undo banner steals exact-fit content space; failures look like success

*(was SOL-U14 + fable FV3/FB18)* Drawer metrics reserve search height but not the
inserted banner (`DrawerMetrics.swift:13-15,95-99`, `DrawerView.swift:63-67`), so the
last grid row is pushed under the fold of the fixed-height drawer while the banner
shows. And a failed Undo currently dismisses as if it succeeded.

**Action (Device):** use an overlay or include banner height and reframe (design pick
plus an on-device look); report failed or partial Undo ("Couldn't put N item(s)
back") instead of dismissing as success.

### U11 P2: Reduced Motion/contrast support is incomplete

*(was SOL-U16)* Main drawer motion respects Reduce Motion, but selection scroll,
group transitions, Undo, sparkles, arrival dots, poof, and color-only running/arrival
states do not consistently honor accessibility display settings.

**Action (Device):** central motion policy, static alternatives, Increase Contrast,
Differentiate Without Color, and custom-fill contrast testing.

### U12 P2: Automatic update discovery can interrupt another app

*(was SOL-U17)* Background checks can activate the app and show a modal.

**Action (Design):** status badge/notification for background discovery; modal only
after Check Now. Add determinate progress and cancellation.

### U13 P3: Main/status menus need conventional cleanup

*(was SOL-U18 + fable FU5 + awesome's ⌘W note)* Regular mode lacks About, Settings,
Services, Hide, File/Close, Window, and Help (`AppDelegate.swift:51-83`); `Cmd-W` has
no conventional route (adding a File menu to an `LSUIElement` agent is a minor product
choice). Eight top-level "New … Tab" rows dominate the status menu.

**Action:** install conventional menus and collapse kinds under a New Tab submenu or
one picker.

### U14 P3: Visual density and object hierarchy need a second pass

*(was SOL-U19 — observations from `screenshot.png`)* Drawer surfaces are much
larger/darker than their sparse content; header actions and counts fade into the
chrome; the tab-to-drawer seam is close but not one object (border, tint, and
elevation differ enough that the pill reads as a sticker); large empty grids have no
intentional rhythm; the notes surface and item grid use different density/edge
treatments without shared header spacing.

**Action (Device design pass):** slightly reduce default footprint, strengthen action
hit regions without making chrome louder than content, tune the tab/drawer seam as one
physical object, and reveal subtle slot affordances only during drag/edit. Avoid more
cards, gradients, or decorative badges.

### U15 P3: Empty states need direct recovery actions

*(was SOL-U20)* Items lacks Add Files/Add Link; missing Folder points at the gear;
Network lacks Connect to Server; Spotlight failure cannot lead to settings.

**Action:** one primary action and one sentence per state. Drag remains the delightful
path, not the only path. Pair with U1's state model.

### U16 P3: Custom images can distort

*(was SOL-U15)* Resizable images use fixed square frames without explicit aspect fit
(`ItemView.swift:309-319`, `TabsView.swift:261-265`).

**Action:** aspect-fit in a square icon box and downsample imports.

### U17 P3: Time buckets can remain stale across midnight

*(was fable FV5)* `TimeBucket.grouped(…, now: Date())` is evaluated in `body`
(`DrawerView.swift:302`); an open Recents/Fresh drawer keeps "Today" until something
re-renders.

**Action:** schedule a lightweight next-midnight refresh or use an appropriate timeline.

### U18 P3: Localization/larger-text resilience is absent

*(was SOL-U21)* The project declares English/Base but has no string catalog; fixed
windows, raw AppKit strings, manual plurals, and fixed columns are English-sized.

**Action:** String Catalog, explicit AppKit localization, plural inflection,
pseudo-localization, RTL/fixed-width review, and resizable utilities if localization
becomes a product goal. If English-only is intentional, state it explicitly.

### U19 P3: About/README product presentation is sparse

*(was SOL-U22)* About lacks project/release/support/privacy/license links. README
uses "Screenshot" alt text and one cropped image of the pre-rename app.

**Action:** restrained links and a current gallery showing drawer, Settings, groups,
classic mode, search, and loading/empty states with descriptive alt text. (A new
screenshot is also rename phase 3 — see section 6.)

### U20 P3: List layout has no explicit empty insertion zones

*(was awesome G15)* Grid reports every slot; list reports existing rows, so
blank-space drops append without between-row/trailing feedback.

**Action (Design):** choose between-row insertion and a clear trailing append zone.

### U21 P3: Hover-open has no intentional dwell

Brushing a hover-enabled pill can open immediately; edge-brushing pops drawers.

**Action (Device):** add a short configurable/system-feeling dwell and a restrained
progress affordance; keep file spring-load timing distinct.

## 5. Feature Roadmap and Delight

Ordered by product value (union of the sol §5 list, fable FF1-FF7, and awesome §4):

1. **Full keyboard navigation plus Quick Look.** Arrow selection across the
   unfiltered grid and Space preview — the most Mac-native missing interactions.
   (Type-to-find already ships; arrowing the full slot grid with gaps is the
   remaining, fiddlier half.)
2. **Relink broken items.** Complete bookmark recovery (see U4).
3. **Move/Copy to Tab.** A context submenu solves most cross-drawer organization
   without a fragile inter-window drag design; a drop on another pill would add a
   copy, not move.
4. **Multi-select and batch actions.** Launch/reveal/remove/move/customize several.
5. **Drag persistent Items entries out.** Live-source items already drag out; the
   main launcher should not be the exception.
6. **Universal search.** One optional Carbon hotkey → a small centered field that
   type-to-finds across all tabs (the per-drawer `DrawerSearch` ranking logic already
   exists), Return launches, with tab/group breadcrumbs. "Spotlight for your
   drawers" — the highest-payoff beyond-DragThing project.
7. **Live Fresh/System Recents while open.** The Spotlight query stops after the
   first gather; keep it live and merge arrivals without reopening (folder tabs
   already live-update).
8. **Spring-loaded folder items.** Hover during a drag to expose nested destinations.
9. **Per-tab icon size and Fresh scopes.** Dense app grids and sparse project drawers
   want different scales; Fresh scopes are hardcoded under `$HOME` today. A per-tab
   override with "use global" default fits the existing `BehaviorMode` pattern.
10. **Separators, headings, and spacers.** A non-launchable divider item kind fits
    the existing slot model.
11. **Duplicate Tab / Shift-drag duplicate.** Fast layout variants, including onto
    another edge/display.
12. **Named layouts/scenes.** Work, Presentation, Travel, docked, undocked.
13. **Complete document undo.** Tab/group/item deletion, grouping, imports, and
    placement — not only file moves.
14. **Disk capacity.** Free-space text, tooltip, and restrained gauge ("231 GB free
    of 1 TB") — data is one `resourceValues` call away (ties into U7).
15. **Global reveal/hide-all hotkey.** Classic DragThing had a global dock-toggle
    key; with auto-hide tabs, one panic key that reveals everything is the safety net
    (per-tab hotkeys exist; a global one doesn't).
16. **Move to Display in the pill menu.** Settings currently owns this path (the pill
    menu has only Move to Edge).
17. **Cloud provider live refresh.** Watch `~/Library/CloudStorage` while open — a
    `DispatchSource` watch wired into open/close/refresh, mirroring the folder
    watcher.
18. **Frecency/Frequent Recents.** Optional launch count plus recency.

Delight backlog (union of the sol and awesome/fable idea lists — none are bugs; each
needs design + visual iteration):

- **Menu-bar Inbox:** drop files on the status item and route to a designated/chosen
  tab — the status item's button is an `NSView`, so `registerForDraggedTypes` works,
  and it is the one drop target visible when every tab is hidden.
- **Tear-off tab packages:** drag a pill to Finder as a single-tab document
  (`TabName.<ext>` JSON export); drop back to import. Shareable, backupable docks.
- **Command-scroll zoom:** ⌘-scroll over an open drawer live-adjusts that tab's icon
  size, Finder-style (backed by roadmap 9's per-tab override).
- **Finder-tag inheritance:** suggest a Folder tab color from the folder's Finder
  label (`.tagNames`, no permission) — never silently override.
- **Parked-tab ghosts:** disconnected tabs appear dimmed in the status menu with the
  display name and a one-click temporary main-screen visit (pairs with R6).
- **Spring-load progress ring / pill "breathe":** while a dragged item hovers a tab
  with the spring-open timer pending, a restrained countdown affordance (charging
  outline, or a 1.00→1.04 scale breathe); static under Reduce Motion.
- **Smart group-name suggestions:** grouping Xcode + Terminal + GitHub may suggest
  "Development" — suggest, never silently rename.
- **Display map placement:** a drag-on-a-diagram widget mirroring System Settings →
  Displays instead of a text-only picker.
- **Classic mechanical feedback:** tiny bevel press and optional haptic in classic
  mode when a drawer opens; no default sounds.
- **Reconnect wave:** stagger parked pills' slide-in by ~40 ms when a display
  returns; Reduce Motion aware.
- **Search upgrades:** initials/fuzzy matching ("xc" → Xcode) with matched-range
  bolding, `Cmd-1…9` to launch the Nth result, Shift-Return to reveal.
- **Search aliases:** short terms like `dl`, `icloud`, `trash`, and provider names
  match common items.
- **Running-app powers:** Quit/Hide in a running app's context menu; Option-click to
  hide others.
- **Versioned single-layout export envelope:** wrap `exportData()` so import errors
  can say "made by a newer version" with clear portability errors.
- **Tab pulse on external change:** one-shot edge glow when a folder/network drawer
  changes while closed; Reduce Motion respected.
- **Dock-edge warning:** when a tab is placed on the Dock edge, hint that
  `visibleFrame` may shift tabs around the Dock.
- **Modifier-hover Peek:** temporarily preview Notes/Fresh/Recents without keying
  search or entering edit mode.
- **Corner Store:** an optional corner target whose four quadrants route drops to
  favorite drawers. Weird, useful, very DragThing.

Intentional non-goals remain: process dock/app switcher, AppleScript dictionary,
free-floating off-edge placement, and default novelty sounds. iCloud sync remains a
separate future project. (Earlier notes also listed accessibility and localization as
non-goals; the sol review supersedes that — keyboard/VoiceOver completeness is
blocker A7, and localization stays conditional per U18.)

## 6. Engineering, Documentation, and Verification

### Engineering/release cleanup

- **Finish the rename machinery (rename phase 3; record in section 7).** The GitHub repo is now
  `L-K-M/TopDrawer`, but the updater still queries `repo: "MacDring"`
  (`AppDelegate.swift:14` — works only via GitHub's rename redirect) and the README
  release link still points at `L-K-M/MacDring/releases`. Update both; take a new
  README screenshot of the renamed app (ties into U19); do the quick
  domain/trademark screen (`topdrawer.app`, USPTO/Swissreg); verify the first release
  under the new name end-to-end (builds "Top Drawer.app", uploads
  `TopDrawer-<v>.zip/.dmg`, mention "formerly MacDring" once in the notes). Optional,
  Xcode-only: rename the project/targets/schemes/`MacDring/` folders (purely
  developer-facing; `.macDring` stays a persisted raw value).
- Add a schema migration dispatch before version 2; version currently exists without
  migration routing.
- Test-host detection currently occurs after real Preferences/TabStore/DisplayRegistry
  initialization (`AppDelegate.swift:7-26`), so tests can read the developer's real
  state. Inject temporary/test services before construction.
- Pin GitHub Actions by commit SHA and Homebrew tool versions where practical; scope
  `contents: write` to publish only; validate numeric release tags; run
  `hdiutil verify` on the DMG.
- Clean trailing whitespace in `DrawerItem.swift`; give notes sizing independent
  constants instead of deriving from icon size; eventually rename drawer `autoHide` to
  `closeOnClickOutside` with Codable/UserDefaults migration to avoid the concealment
  naming collision.
- Replace stale source-comment references to historical analysis IDs with durable PR
  links as those lines are touched; until then the legacy ID index in section 7 keeps
  them resolvable.

### Documentation reconciliation

- Update PLAN's model for groups and current shipped features/non-goals; remove
  duplicated Folder prose and stale phase/post-v1 animation/import text; PLAN still
  promises a visible restore offer and Relink (U4), neither exists yet.
- Correct first-run text: Apps plus Welcome, not one starter tab.
- Align recovery text with automatic quarantine/backup behavior and the future health
  UI (A4).
- Correct Folder "read-only" language because drops move files into it (R4).
- Stop claiming Settings `+` creates every tab kind until U2 lands.
- Explain exported JSON sensitivity: notes, bookmarks, URLs, usernames/paths, icon
  paths; bookmarks may not be portable.
- Reconcile root and `.github` CI/CD docs; explain `scripts/build.sh`'s external
  helper (the shared `lkm-build` engine) in README.

### Highest-priority automated coverage

1. Partially lossy decode blocks/surfaces destructive rewrite.
2. Future-version store rejects mutation rather than accepting ephemeral edits.
3. Drawer+riding-tab+nudge containment for every edge.
4. Unknown-display import mapping and duplicate ID validation.
5. Malformed top-level Recents preservation.
6. Folder watcher replacement at the same path.
7. Live-source loading/error/timeout/generation state.
8. Operation queue progress, partial move/Undo/eject failure, and cancellation.
9. Favicon response bounds/private-host policy and privacy preference.
10. App lifecycle service construction/teardown and monitor/source counts.
11. Release artifact Info.plist/resources/entitlements/signature/DMG/minimum-OS smoke test.

### Manual macOS matrix

- Focus under click/hotkey/hover/spring open from another app's text field and IME.
- VoiceOver, Accessibility Inspector, keyboard-only grid/list/group/search, Increase
  Contrast, Differentiate Without Color, Reduce Motion/Transparency.
- Multiple displays: shared edges, negative coordinates, Dock edges, resolution and
  orientation changes, disconnect/reconnect, main-display swap, clamshell, Stage Manager.
- Spaces/fullscreen and Floating/Normal window levels.
- Huge/network/offline folders, sleeping/ejecting volumes, cloud providers appearing.
- Group/search drops onto apps/folders/Trash; cross-volume moves and partial failures.
- Long/empty names, 12x16 at 128 points, laptop visible frames, larger text/localization.
- Icon editor Save/Use Default/Cancel/title-close and intervening drawer interactions.
- Carbon duplicate handoff and ServiceManagement approval states.
- Delight-batch visuals that never had hands-on review: drag snap haptics, drag-over
  peek, trash poof, Fresh sparkle, Appearance live preview, favicon fetching.
- Packaged app, Gatekeeper instructions, DMG verification, updater download.

## 7. History and Completed-Work Index

This section preserves the context of finished work so source comments, PLAN
references, and old finding IDs stay meaningful. Everything here is **done** — any
follow-up becomes a new item in the active sections above. Full prose for each
finding lives in git history (`git log --diff-filter=D -- awesome.md
fable-is-awesome.md sol.md NAMING.md`, and earlier revisions of this file — named
`ANALYSIS.md` until 2026-07-11, so use `git log --follow`). Old status claims in
those historical revisions ("nothing P0-P1 remains", "through PR #32") were wrong
when written and must not be treated as current.

### Product rename (July 2026)

MacDring → **Top Drawer**. Finalists were Top Drawer and Corner Store; Corner Store
was eliminated on clearance (existing CornerStore apps, and convenience-retail POS
software owning the phrase in search) and on accuracy (the app lives on edges, not
corners). An earlier model-generated shortlist (Drawledge, Brimfold, ScreenSill, …)
was vetted and declined. The full research and vetting tables lived in `NAMING.md`,
deleted 2026-07-11 — recoverable from git history like the review documents above.

Phases 1 (user-visible identity) and 2 (built product `Top Drawer.app`, release
pipeline, icon artwork) are done; the phase 3 leftovers are an active item in
section 6.

**Deliberately unchanged, with reasons** — don't "finish" these without a migration
plan:

- Bundle ID `com.macdring.MacDring`: changing it resets user defaults, saved
  layouts, and Automation/permission grants. Keep, or ship a migration.
- Application Support directory `MacDring/` (`TabStore.defaultStoreURL`): renaming
  it orphans every user's saved layout. Keep, or migrate on launch.
- The Swift module: `PRODUCT_MODULE_NAME` is pinned to `MacDring`. (The rename sweep
  briefly let it derive as `Top_Drawer` from the new product name, which broke every
  test's `@testable import` and blocked the v2.0.0 release gate.)
- Code identifiers (`RecentsSource.macDring`, `includesMacDring`, `MacDringMain`):
  `.macDring` is a persisted raw value in saved documents; rename only with Xcode.
- Frame autosave name `MacDringSettingsWindow`: a defaults key.

### Early history (pre-review batches)

The original DragThing gap analysis (B1-B12) and parity features merged through
PR #32: Trash, layout import/export, rename/change-icon, tab reorder + Move to Edge,
auto-hide/fade, Disks/Network/Cloud tabs, per-tab behavior overrides, custom item
icons, and robustness fixes. Later batches through PR #60 added Recents/Fresh,
search/type-to-find, running-app dots, folder-tab niceties, stable transient IDs,
adaptive drawer chrome, status-menu tab access, and the Welcome/checklist/delight
batch (snap haptics, undo toast, trash poof + watch, self-healing bookmarks, checklist
notes, Appearance live preview, drag-over peek, Eject All, favicons, Fresh
sparkle/pill dot, folder truncation badge, time buckets, cloud-provider branding).

### Fable review set (2026-07-02, merged as PRs #61-#84)

| PR | Findings | Scope |
|---|---|---|
| [#61](https://github.com/L-K-M/TopDrawer/pull/61) | FB1 + FP4 + FP5 | Fresh pipeline Spotlight-only: no TCC prompts, badge rescans only on timer/appearance, no double-scan/query starvation (subsumed G19) |
| [#62](https://github.com/L-K-M/TopDrawer/pull/62) | FB2 | Persist de-overlap only on the tab's own anchored display (guest-display anchor corruption) |
| [#63](https://github.com/L-K-M/TopDrawer/pull/63) | FB3 + FF6 | Reject Shift-only hotkeys; allow bare function keys F1-F20 |
| [#64](https://github.com/L-K-M/TopDrawer/pull/64) | FB4 | Per-element failable Recents decoding |
| [#65](https://github.com/L-K-M/TopDrawer/pull/65) | FB5 + FP1 + FP2(nonce) | Favicon no longer stomps custom icons; ItemView `.task` I/O off-main; trash nonce scoped to trash items |
| [#66](https://github.com/L-K-M/TopDrawer/pull/66) | FB6 + FV4 | Undo toast cleared on tab load/hide; animated transition |
| [#67](https://github.com/L-K-M/TopDrawer/pull/67) | FB7 + FB19 | Bookmark sweep covers folder/custom-icon bookmarks; import adopts document version |
| [#68](https://github.com/L-K-M/TopDrawer/pull/68) | FB8 | Drag-over peek gated on pasteboard changeCount, cached per drag |
| [#69](https://github.com/L-K-M/TopDrawer/pull/69) | FB9 | Folder slot drops resolve against displayed items, not a re-list |
| [#70](https://github.com/L-K-M/TopDrawer/pull/70) | FB10 | Only items/folder pills register for file drops |
| [#71](https://github.com/L-K-M/TopDrawer/pull/71) | FB11 + FU3 | Dialogs float above the drawer; Empty Trash states the item count |
| [#72](https://github.com/L-K-M/TopDrawer/pull/72) | FP3 (fixes FB13 + FB14) | Stable path+kind-derived IDs for transient items |
| [#73](https://github.com/L-K-M/TopDrawer/pull/73) | FB15 + FP9 | Favicon in-flight dedup, only definitive failures pinned; cache capped/downscaled |
| [#74](https://github.com/L-K-M/TopDrawer/pull/74) | FB16 | Shared line normalization for checkbox toggling (CRLF/U+2028) |
| [#75](https://github.com/L-K-M/TopDrawer/pull/75) | FB17 + FP6(guards) | No drop advertising without a resolvable folder; equality-guarded drag-hover writes |
| [#76](https://github.com/L-K-M/TopDrawer/pull/76) | FB20 | Honest "couldn't parse version" update result |
| [#77](https://github.com/L-K-M/TopDrawer/pull/77) | FB21 + FB22 | New Tab dialog drops stale folder fields; grid stepper ranges aligned |
| [#78](https://github.com/L-K-M/TopDrawer/pull/78) | FB23 | Cloud branding no longer matches bare "drive" |
| [#79](https://github.com/L-K-M/TopDrawer/pull/79) | FV1 + FB24 | Readable pill foreground on light colors; monogram caps aligned |
| [#80](https://github.com/L-K-M/TopDrawer/pull/80) | FP2(debounce) | Trash watch debounced |
| [#81](https://github.com/L-K-M/TopDrawer/pull/81) | FP7(guards) | Equality-guarded pill model writes |
| [#82](https://github.com/L-K-M/TopDrawer/pull/82) | FV2 + FU1 + FU4 | Appearance-adaptive drawer chrome; scroll-to-selection; correct Recents empty copy |
| [#83](https://github.com/L-K-M/TopDrawer/pull/83) | FU2 | Status-menu Tabs section opens any tab's drawer |
| [#84](https://github.com/L-K-M/TopDrawer/pull/84) | FI2 + FI6 + FI7 | Welcome checklist note; poof on context-menu remove; spring-open haptic |

Fable items that stayed open were folded into the active sections: FB12→R7, FB18→A4/U10,
FP6's index half→P10, FP7's cache half→P11, FP8→P6, FP10→R10/P7, FV3→U10, FV5→U17,
FU5→U13, FF1-FF5/FF7→roadmap, FI1/FI3-FI5/FI8-FI10→delight.

### Sol review set (2026-07-10, merged as PRs #85-#100)

PRs #85-#100 were updated onto the advancing `main` and passed macOS Build & Test
before merge; integration conflicts retained both sides' tests and behavior, and #97
gained a regression test for bounded batch placement.

| Finding | PR | Scope |
|---|---|---|
| SOL-B04 | [#85](https://github.com/L-K-M/TopDrawer/pull/85) | Group child decode/mutation/bookmark integrity; group-test UUID compilation |
| SOL-B01 | [#86](https://github.com/L-K-M/TopDrawer/pull/86) | Field-wise Settings edits prevent stale whole-tab overwrites (ex awesome B5/G9) |
| SOL-B02 | [#87](https://github.com/L-K-M/TopDrawer/pull/87) | Recover/reject semantically corrupt all-tabs-dropped documents |
| SOL-B03 | [#88](https://github.com/L-K-M/TopDrawer/pull/88) | Bound persisted dimensions, slots, orders, mutation, and grid rendering |
| SOL-B12 | [#89](https://github.com/L-K-M/TopDrawer/pull/89) | Consistent custom-icon precedence and editor close/reopen behavior |
| SOL-B09 | [#90](https://github.com/L-K-M/TopDrawer/pull/90) | Confirm launch success before Recents/drawer effects |
| SOL-B05 | [#91](https://github.com/L-K-M/TopDrawer/pull/91) | Identity-bearing external drop targets for groups/search |
| SOL-B11 | [#92](https://github.com/L-K-M/TopDrawer/pull/92) | Fully keyed, cached Spotlight drawer work |
| SOL-B10 | [#93](https://github.com/L-K-M/TopDrawer/pull/93) | Retry app-owned hotkey conflicts after release |
| SOL-B15 | [#94](https://github.com/L-K-M/TopDrawer/pull/94) | Preserve exact 0/1 edge anchors |
| SOL-B17 | [#95](https://github.com/L-K-M/TopDrawer/pull/95) | Atomic export with surfaced errors |
| SOL-B18 | [#96](https://github.com/L-K-M/TopDrawer/pull/96) | Reject no-op link-only Trash drops |
| SOL-P01 | [#97](https://github.com/L-K-M/TopDrawer/pull/97) | Batch multi-item drop mutation/reconcile/save |
| SOL-B26 | [#98](https://github.com/L-K-M/TopDrawer/pull/98) | Supported update assets, HTTPS, size verification, temp cleanup |
| SOL-U05 | [#99](https://github.com/L-K-M/TopDrawer/pull/99) | Live Add Link validation and normalization |
| SOL-P02 | [#100](https://github.com/L-K-M/TopDrawer/pull/100) | Cancel/identity guard for group preview icons |

Sol items that stayed open were folded into the active sections: B06→A1, B07→A2,
B08/B20→A3, B13→A4, B14→R1, B16→R2, B19→R5, B21→R3, B22→R4, B23→R7, B24→R6, B25→R8,
B26(signing)→A6, B27→A5, B28→R15, P02(bounded resolver)→P5, P03→P1, P04→P2, P05→P3,
P06→P4, P07→P6, P08→P7, U01→A7, U02→A4, U03→U1, U04→A8, U06→U2, U07→U3, U08→U4,
U09→U5, U10→U6, U11→U7, U12→U8, U13→U9, U14→U10, U15→U16, U16→U11, U17→U12, U18→U13,
U19→U14, U20→U15, U21→U18, U22→U19.

### Legacy source-comment ID index

Source comments (and `PLAN.md`) cite legacy finding IDs that originated in the
pre-consolidation documents named below — including revisions squashed out of git
history — and point at this index to resolve them (FB1/FP1 citations also carry
their PR links inline; the ex-B28 citation points at the open item R14). Meanings,
reconstructed from the citing sites:

| Cited as | Meaning (all shipped unless noted) | Cited from |
|---|---|---|
| ANALYSIS.md B3 | Guard against opening/moving a drawer onto a detached display | `TabController.swift` |
| ANALYSIS.md B7 | Preserve the notes editor's selection and in-flight (marked) input across drawer refreshes | `DrawerWindowController.swift` |
| ANALYSIS.md B8 | Don't re-arm the pill frame-defender while an earlier run is still in flight | `TabWindowController.swift` |
| ANALYSIS.md I1 | Live-listing items don't mint/persist bookmarks; read paths fall back to `url` (avoids `makeBookmark` churn per refresh) | `DrawerItem.swift`, `FolderLister.swift`, `FreshLister.swift` |
| ANALYSIS.md I2 | Cached, off-render-path drawer icon resolution (extended off-main by FP1/PR #65) | `ItemView.swift` |
| ANALYSIS.md I3 | Per-tab behavior overrides: the global setting is a live default; the `updateAllBehaviors` bulk-overwrite is gone | `TabBehavior.swift`, `TabsView.swift`, `TabController.swift`, `PLAN.md` |
| ANALYSIS.md I4 | Slot normalization is bounded and keeps items in place; drop ordering stays stable during async icon loads | `TabStore.swift`, `TabStripView.swift` |
| ANALYSIS.md I5 | Trash count uses a home-`~/.Trash`-only, subdirectory-only metadata check | `TrashInspector.swift` |
| ANALYSIS.md C2 | The activation-policy guard (`.accessory`/`.regular` switching) | `ActivationPolicy.swift` |
| awesome.md B28 | Trash metadata count includes `.DS_Store` — **still open as R14** | `TrashInspector.swift` |
| fable-is-awesome.md FB1 | Fresh tab TCC prompts; `FreshScanner` retired from the live path to Spotlight-only (PR #61), then restored behind the explicit opt-in `Preferences.freshDirectScan` (Settings → General) for Macs where Spotlight is unreliable | `FreshScanner.swift`, `FreshLister.swift`, `TabController.swift`, `DrawerWindowController.swift` |
| fable-is-awesome.md FP1 | ItemView `.task` filesystem/icon I/O moved off the main thread (PR #65) | `ItemView.swift` |
