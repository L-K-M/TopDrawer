# MacDring: Open Backlog

Canonical, forward-looking backlog after the full review at `main` commit `512bff0`
on 2026-07-10. The review snapshot, evidence, exact source references, implemented
patch set, and naming research live in [`sol.md`](sol.md). Completed work is kept out
of the active backlog below; implemented PRs and historical references have compact
indexes so source comments and earlier analysis IDs do not lose their context.

Severity: **P0** data loss, **P1** major correctness/security/accessibility,
**P2** robustness/performance/UX, **P3** polish. Labels:

- **Design**: decide the product behavior before implementation.
- **Device**: validate on a real Mac; static review is not sufficient.
- **Project**: a coherent feature/refactor, not a drive-by patch.

macOS CI is the source of truth for compilation and unit tests. Multi-monitor
windowing, focus, Spaces/fullscreen, AppKit drag sessions, Carbon/ServiceManagement,
accessibility, and visual behavior need the manual matrix in section 7.

## 1. Implemented Review Set

These findings were implemented and merged through isolated PRs and are not duplicated
in the active backlog. Any review follow-up becomes a new active item.

PRs #85-#100 were updated onto the advancing `main` and passed macOS Build & Test
before merge. Integration conflicts retained both sides' tests and behavior; #97 also
gained a regression test for bounded batch placement.

| Finding | Merged pull request | Scope |
|---|---|---|
| SOL-B04 | [#85](https://github.com/L-K-M/MacDring/pull/85) | Group child decode/mutation/bookmark integrity; also fixes current group-test UUID compilation |
| SOL-B01 | [#86](https://github.com/L-K-M/MacDring/pull/86) | Field-wise Settings edits prevent stale whole-tab overwrites |
| SOL-B02 | [#87](https://github.com/L-K-M/MacDring/pull/87) | Recover/reject semantically corrupt all-tabs-dropped documents |
| SOL-B03 | [#88](https://github.com/L-K-M/MacDring/pull/88) | Bound persisted dimensions, slots, orders, mutation, and grid rendering |
| SOL-B12 | [#89](https://github.com/L-K-M/MacDring/pull/89) | Consistent custom-icon precedence and editor close/reopen behavior |
| SOL-B09 | [#90](https://github.com/L-K-M/MacDring/pull/90) | Confirm launch success before Recents/drawer effects |
| SOL-B05 | [#91](https://github.com/L-K-M/MacDring/pull/91) | Identity-bearing external drop targets for groups/search |
| SOL-B11 | [#92](https://github.com/L-K-M/MacDring/pull/92) | Fully keyed, cached Spotlight drawer work |
| SOL-B10 | [#93](https://github.com/L-K-M/MacDring/pull/93) | Retry MacDring-owned hotkey conflicts after release |
| SOL-B15 | [#94](https://github.com/L-K-M/MacDring/pull/94) | Preserve exact 0/1 edge anchors |
| SOL-B17 | [#95](https://github.com/L-K-M/MacDring/pull/95) | Atomic export with surfaced errors |
| SOL-B18 | [#96](https://github.com/L-K-M/MacDring/pull/96) | Reject no-op link-only Trash drops |
| SOL-P01 | [#97](https://github.com/L-K-M/MacDring/pull/97) | Batch multi-item drop mutation/reconcile/save |
| SOL-B26 | [#98](https://github.com/L-K-M/MacDring/pull/98) | Supported update assets, HTTPS, size verification, temp cleanup |
| SOL-U05 | [#99](https://github.com/L-K-M/MacDring/pull/99) | Live Add Link validation and normalization |
| SOL-P02 | [#100](https://github.com/L-K-M/MacDring/pull/100) | Cancel/identity guard for group preview icons |

## 2. Release-Quality Blockers

### A1 P1: Future-version documents accept edits that can never save

`TabStore` correctly refuses to rewrite a document from a newer schema, but all
mutations remain enabled. Work appears to succeed and disappears after restart.

**Action (Design):** publish a read-only `StoreHealth` state, disable mutation, explain
that the document was created by a newer version, and offer export or explicit layout
replacement. Build this with A4 rather than adding isolated alerts.

### A2 P1: Hover-open can redirect typing from the foreground app

The nonactivating drawer still becomes key and auto-focuses search. Crossing a hover
tab while typing elsewhere can redirect subsequent input without a click.

**Action (Design + Device):** carry an open reason (`click`, `hotkey`, `hover`,
`springLoad`). Hover/spring opens remain pointer-only; acquire key/search focus only
after explicit keyboard intent or a click into an input. Verify against another app's
text field and input methods. Do not add a global key monitor.

### A3 P1: Portable imports can park every foreign-display tab

Unknown display UUIDs follow the disconnected-display policy; default Park hides the
imported tabs. README promises cross-machine movement and PLAN promises fallback.

**Action (Design):** add an import display-mapping step, defaulting unknown UUIDs to
the current main display. Distinguish portable import from same-machine restore.
Also validate duplicate tab/item UUIDs, maximum counts, and sensitive/path-bearing
content before replacement.

### A4 P1: Persistence health and operation failures are mostly invisible

Save failures, backup recovery, quarantine, partial lossy decode, malformed Recents,
future-version read-only mode, failed launch/eject/move/Undo/Empty Trash, and live-source
failures are logs, silent dismissal, or indistinguishable empty states.

**Action (Project):** introduce durable `StoreHealth` and transient `OperationStatus`.
Expose a status-item badge and accessible Settings/drawer banners with Retry, Reveal
Data Folder, Relink, or Open Settings actions. Preserve partially lossy originals and
require acknowledgement before rewriting. Distinguish absent Recents data from corrupt
top-level JSON so the next launch does not overwrite recoverable bytes.

### A5 P1: Remote favicons make undisclosed requests to arbitrary hosts

Opening link drawers requests `/favicon.ico`, revealing hosts and potentially contacting
local/private services. `URLSession.data` can buffer an unbounded response.

**Action (Design):** add a privacy disclosure and preference; choose whether remote
favicons default on. Use short timeouts and bounded streaming, and define policy for
loopback/private destinations. Document automatic GitHub checks and local launch
history in the same privacy section.

### A6 P1: Distribution/update chain is unsigned and not release-grade

Releases are ad-hoc signed, not Developer ID signed/notarized/stapled. Strict asset
selection is in PR #98, but there is still no cryptographic update signature or
checksum. README's entitlement wording does not describe the shipped ad-hoc artifact
accurately.

**Action (Project):** Developer ID sign with hardened runtime and entitlements,
notarize, staple, verify with strict `codesign`, and use a signed feed such as Sparkle
EdDSA. Until then, call downloads a convenience and retain honest Gatekeeper/manual
installation copy.

### A7 P1: Core drawers are not keyboard/VoiceOver complete

Tabs/items are gesture surfaces rather than a complete control/selection model.
Unfiltered drawers, short drawers without search, groups, and context actions do not
have full keyboard paths; explicit accessibility labels/values/actions are sparse.

**Action (Project + Device):** build one selection model for grid/list/group/search.
Support arrows, Home/End, Return, Space, Delete, context actions, and `Cmd-F` regardless
of item count. Announce item type, broken/running/ejecting state, group count, and tab
open state. Validate with VoiceOver and Accessibility Inspector.

### A8 P1: Destructive layout actions have no complete undo/confirmation model

Tab deletion, group deletion, item removal, Clear Recents, imports, and grouping can be
irreversible. A group can hide many launchers behind one Delete Group action.

**Action (Design):** add document-level undo. Until then, confirm populated tab/group
deletion with counts. Prefer an accessible Undo banner over repeated modal alerts.

## 3. Correctness and Runtime Risks

### R1 P2: Passive reconciles can permanently rewrite stable anchors

De-overlap persists positions during screen/appearance reconciliation. Temporary
resolution, Dock visible-frame, label, or thickness changes can become permanent.
The guest-display corruption is fixed, but anchored-display transient geometry remains.

**Action (Design + Device):** separate requested persisted anchors from transient
collision resolution. Persist collision settlement after explicit user operations, not
passive environment changes. Test resolution/Dock/appearance round trips.

### R2 P2: Maximum drawers can push the riding tab/animation off-screen

Drawer caps do not reserve the riding tab thickness or 22-point animation nudge.

**Action (Device):** cap perpendicular depth using one envelope containing drawer,
riding tab, and nudged frame. Add pure containment tests for every edge and small
visible frames before changing live geometry.

### R3 P2: Click-outside misses MacDring's own windows

The global mouse monitor cannot see same-process clicks, so Settings/New Tab/status-menu
interactions can leave the popup drawer above ordinary windows.

**Action (Device):** add a filtered local mouse monitor or explicitly close before
ordinary-window actions. Never dismiss clicks inside the active drawer/pill.

### R4 P2: Drop cursor advertises Copy for Move/Trash operations

Folder targets move sources and Trash removes them while AppKit always returns Copy.

**Action (Design):** after identity targeting lands, choose target-sensitive operations
and Finder modifier semantics: add reference, open-with, move/copy, and Trash. Report
partial failures and correct README's “read-only folder” language.

### R5 P2: Folder watch can remain attached to a deleted vnode

Reuse is path-based although the dispatch source watches a descriptor/vnode. A
replacement folder at the same path may not refresh.

**Action (Device):** inspect event flags and reopen on delete/rename/revoke, with retry
when a replacement is not ready.

### R6 P2: Parked status-menu rows are enabled but cannot open

The menu is described as the hidden-tab recovery route, yet parked tabs have no live
screen and `openDrawer` rejects them.

**Action (Design):** mark the display as disconnected and offer “Show Temporarily on
Main Display” without anchor mutation plus “Move to Main Display.”

### R7 P2: Pending Launch at Login approval is misrepresented

`SMAppService.Status.requiresApproval` falls through to stale/unknown state, and Off
does not necessarily unregister pending approval.

**Action (Device):** model enabled, disabled, pending approval, unavailable, and error;
offer Open Login Items Settings; test state transitions on supported macOS versions.

### R8 P2: Live icon override keys are path-only

Non-file URLs with the same path can collide, especially root links.

**Action:** use standardized file paths for file URLs and absolute strings for other
URLs; read legacy path keys as a migration fallback.

### R9 P2: Interrupted tab drags have no fallback cancellation

If a pill disappears during SwiftUI drag (display disconnect, removal, forced order
out), `.onEnded` may not clear drag state, leaving concealment disabled for that tab.

**Action (Device):** add an AppKit mouse-up/cancel fallback and clear drag state when
reconcile removes or parks the dragged window.

### R10 P2: Direct frame updates can race in-flight animations

Refresh/live-item frame changes and pill updates can set frames while an animation has
an older target; completion may leave the riding pill/drawer misaligned until another
reconcile.

**Action (Device):** observe rapid open/close/switch, live-list resize, and preference
changes; cancel/reassert animation targets using a generation if reproduced.

### R11 P3: Classic drag preview uses modern sizing assumptions

The drag frame does not mirror all classic fitting behavior and may clip transiently.

**Action (Device):** compare classic placement and cross-edge drag preview sizing, then
share the sizing calculation if confirmed.

### R12 P3: Folder-item drops silently discard browser links

Folder moves filter to file URLs. The target can still look actionable depending on
the drag source/context.

**Action (Design):** choose refusal, add-to-tab fallback, or creation of a `.webloc`;
advertise only the chosen operation.

### R13 P3: Hotkey recorder monitor lifetime needs a backstop

Teardown relies on SwiftUI `onDisappear`; a surviving local monitor could swallow
key-down events.

**Action (Device):** verify window/focus lifecycle and add resign/timeout cleanup if
needed. Surface Carbon registration conflict/reserved status in Settings and warn
against common one-modifier editing shortcuts.

### R14 P3: Trash metadata count can include `.DS_Store`

The count badge/confirmation may say full when Finder appears empty.

**Action (Device):** find a permission-safe enumeration/metadata strategy that excludes
Finder bookkeeping without triggering Trash access prompts.

### R15 P3: Teardown omits sources and delayed work

The Trash watch and several work items are not cancelled by `saveAndTeardown`.

**Action:** make teardown idempotently cancel every monitor, dispatch source, observer,
timer, query, and delayed work item; consider safe `deinit` assertions.

## 4. Performance and Responsiveness

### P1 P1: File move, Trash, Undo, Empty Trash, and single eject block the main thread

Cross-volume/network operations can beachball the drag session for seconds or minutes.
Empty Trash also executes synchronous `NSAppleScript` on the main thread.

**Action (Project):** use a bounded serial utility queue with operation IDs,
progress/busy state, cancellation where possible, partial-result reporting, and
main-actor application. Do not detach work without ownership.

### P2 P1: Folder opening enumerates/stats/sorts everything on-main

The 300 cap bounds output, not enumeration work; unrelated reconciles can repeat it.

**Action (Project):** gather asynchronously with a generation key and explicit
loading/error state. Use bounded top-N selection preserving folders-first and chosen
sort. Apply only if tab/path/config still match.

### P3 P2: Settings resolves row icons synchronously

Large, broken, or network-backed item lists can stutter Settings scrolling.

**Action:** use an async cached row model during the planned selectable Settings item
manager redesign.

### P4 P2: Bookmark resolution can mount/show UI in quiet paths

Display, deduplication, and background repair use the same resolution policy as
explicit launch.

**Action (Design):** use quiet `.withoutUI`/`.withoutMounting` policies for display,
dedup, and repair; reserve user-interactive resolution for launch/relink.

### P5 P2: Icon work is unbounded despite cancellation guards

PR #100 prevents stale group assignments, but hundreds of detached filesystem/icon
tasks can still outlive rapid open/close cycles.

**Action (Project):** centralize icon resolution in a bounded cache/service with
cancellation and request coalescing.

### P6 P3: Notes preview reparses on unrelated drawer invalidations

Long notes are classified/Markdown-parsed in a non-lazy stack whenever the shared model
changes.

**Action:** cache parsed lines by text and use lazy rendering during a notes-model pass.

### P7 P3: Spotlight work needs timeout/error/live-state ownership

Queries have no timeout/failure distinction; badge work can overlap long gathers.

**Action:** fold query generation, timeout, loading/error state, and live updates into
the live-source state project (U1), not more independent timers.

### P8 P3: Trash/context metadata work can be unexpectedly expensive

Trash count scans mounted volumes while opening context UI; synchronous bookmark dedup
can also touch network targets.

**Action:** cache/coalesce metadata and apply the quiet bookmark policy from P4.

### P9 P3: Settings still reconciles on every field keystroke

PR #86 prevents stale whole-tab overwrites, but field bindings still create one store
mutation and full controller reconcile per title/monogram keystroke.

**Action:** coalesce high-frequency Settings text edits or separate persistence publish
from window reconciliation while preserving immediate visual feedback and crash-safe
save behavior.

## 5. UX, Visual, and Product Work

### U1 P1: Live sources need loading/empty/unavailable/failed states

Fresh/System Recents, folder, cloud, and network failures collapse into “empty.”

**Action (Project):** shared `.idle/.loading/.content/.empty/.unavailable/.failed`
state with Retry, Choose Folder, Connect to Server, or Open Spotlight Settings.
Keep Spotlight live while Fresh/System Recents drawers are open.

### U2 P2: Settings `+` bypasses the canonical New Tab flow

It creates only a generic Items tab although documentation promises every kind.

**Action (Design):** route menu and Settings through one New Tab flow with icon, title,
and one-line descriptions. Make utility windows resizable/minimum-sized for larger text
and localization.

### U3 P2: Settings is not a keyboard-first item manager

No selection, visible remove/reorder, group expansion, Relink, Move to Tab, or full
keyboard actions.

**Action (Project):** selectable List/Table with add/remove/reorder/reveal/relink/move
controls and async icons. This should share the selection/accessibility work in A7.

### U4 P2: Broken items cannot be relinked

PLAN promises Relink, but the only remedy is remove/re-add.

**Action:** open a seeded picker and preserve item ID, slot, name, and icon while
re-minting the target bookmark. Add a visible/accessibility missing-item state.

### U5 P2: Long labels and maximum grids can clip/overflow

Tab labels are fixed and unbounded. Legal 12-column/128-point settings can create
content wider than a laptop drawer.

**Action (Device):** cap tab length with truncation and full tooltip/accessibility text.
Make effective grid columns/icon size display-aware or provide horizontal navigation
and footprint warning/preview.

### U6 P2: Header controls are faint, small, and under-labelled

The current screenshot shows low-emphasis glyph-only actions with small hit regions.

**Action:** 24-28 point hit areas, hover/focus backgrounds, labels/hints, clear
destructive states, and a status-item tooltip/accessibility label.

### U7 P2: List columns are not source/data aware

Date reserves 96 points even for Items, Disks, Network, and Cloud rows with no date.

**Action:** dates for Folder/Recents/Fresh, capacity for Disks, and name-first ordinary
Items. Add capacity/free-space metadata and an optional subtle volume gauge.

### U8 P2: Notes preview hides Edit

Click-anywhere is the sole editing affordance and conflicts with selection/future links.

**Action:** labelled Edit header action and shortcut; retain whole-surface click only as
a convenience.

### U9 P2: Group/search context and counts are misleading

Header count is top-level only; flattened child results have no parent breadcrumb.

**Action:** show group/item totals, current-group count, and parent/path subtitles in
search results.

### U10 P2: Undo banner steals exact-fit content space

Drawer metrics reserve search but not the inserted banner.

**Action (Device):** use an overlay or include banner height and reframe; report failed
or partial Undo instead of dismissing as success.

### U11 P2: Reduced Motion/contrast support is incomplete

Selection scroll, groups, Undo, sparkles, arrival dots, poof, and color-only states do
not consistently honor accessibility display settings.

**Action (Device):** central motion policy, static alternatives, Increase Contrast,
Differentiate Without Color, and custom-fill contrast testing.

### U12 P2: Automatic update discovery can interrupt another app

Background checks can activate MacDring and show a modal.

**Action (Design):** status badge/notification for background discovery; modal only
after Check Now. Add determinate progress and cancellation.

### U13 P3: Main/status menus need conventional cleanup

Regular mode lacks About, Settings, Services, Hide, File/Close, Window, and Help;
`Cmd-W` has no conventional route. Eight New Tab rows dominate the status menu.

**Action:** install conventional menus and collapse kinds under New Tab or one picker.

### U14 P3: Visual density and object hierarchy need a second pass

Drawers are large dark slabs around sparse content; header actions disappear; tab and
drawer can read as separate layers rather than one object; empty grid material has no
intentional rhythm.

**Action (Device design pass):** slightly reduce default footprint, strengthen action
hit regions without making chrome louder than content, tune the tab/drawer seam as one
physical object, and reveal subtle slot affordances only during drag/edit. Avoid more
cards, gradients, or decorative badges.

### U15 P3: Empty states need direct recovery actions

Items lacks Add Files/Add Link; missing Folder points at the gear; Network lacks
Connect; Spotlight failure cannot lead to settings.

**Action:** one primary action and one sentence per state. Drag remains the delightful
path, not the only path.

### U16 P3: Custom images can distort

Resizable images use fixed square frames without explicit aspect fit.

**Action:** aspect-fit in a square icon box and downsample imports.

### U17 P3: Time buckets can remain stale across midnight

An open Recents/Fresh drawer has no midnight invalidation.

**Action:** schedule a lightweight next-midnight refresh or use an appropriate timeline.

### U18 P3: Localization/larger-text resilience is absent

No string catalog; fixed windows, raw AppKit strings, manual plurals, and fixed columns
are English-sized.

**Action:** String Catalog, explicit AppKit localization, plural inflection,
pseudo-localization, RTL/fixed-width review, and resizable utilities if localization
becomes a product goal. If English-only is intentional, state it explicitly.

### U19 P3: About/README product presentation is sparse

About lacks project/release/support/privacy/license links. README uses “Screenshot” alt
text and one cropped image.

**Action:** restrained links and a current gallery showing drawer, Settings, groups,
classic mode, search, and loading/empty states with descriptive alt text.

### U20 P3: List layout has no explicit empty insertion zones

Grid reports every slot; list reports existing rows, so blank-space drops append without
between-row/trailing feedback.

**Action (Design):** choose between-row insertion and a clear trailing append zone.

### U21 P3: Hover-open has no intentional dwell

Brushing a hover-enabled pill can open immediately.

**Action (Device):** add a short configurable/system-feeling dwell and a restrained
progress affordance; keep file spring-load timing distinct.

## 6. Feature Roadmap and Delight

Ordered by product value:

1. **Full keyboard navigation plus Quick Look.** Arrow selection and Space preview.
2. **Relink broken items.** Complete bookmark recovery.
3. **Move/Copy to Tab.** Context submenu solves most cross-drawer organization.
4. **Multi-select and batch actions.** Launch/reveal/remove/move/customize several.
5. **Drag persistent Items entries out.** Live entries already can.
6. **Universal search.** One Carbon hotkey across all tabs with group/tab breadcrumbs.
7. **Live Fresh/System Recents while open.** Stream Spotlight updates.
8. **Spring-loaded folder items.** Nested drop destinations.
9. **Per-tab icon size and Fresh scopes.** Dense/sparse drawers need different scale.
10. **Separators, headings, and spacers.** Natural fit for the slot model.
11. **Duplicate Tab / Shift-drag duplicate.** Fast variants.
12. **Named layouts/scenes.** Work, Presentation, Travel, docked, undocked.
13. **Complete document undo.** Delete/group/import/placement, not only file moves.
14. **Disk capacity.** Free-space text, tooltip, and restrained gauge.
15. **Global reveal/hide-all hotkey.** Safety net for concealed tabs.
16. **Move to Display in the pill menu.** Settings currently owns this path.
17. **Cloud provider live refresh.** Watch `~/Library/CloudStorage` while open.
18. **Frecency/Frequent Recents.** Optional launch count plus recency.

Delight backlog:

- **Menu-bar Inbox:** drop on the status item and route to a designated/chosen tab.
- **Tear-off tab packages:** drag a pill to Finder as a single-tab document; drop back
  to import.
- **Command-scroll zoom:** resize that tab's icons directly, Finder-style.
- **Finder-tag inheritance:** suggest a Folder tab color from its Finder label.
- **Parked-tab ghosts:** disconnected display name plus temporary main-screen visit.
- **Spring-load progress ring/breathe:** restrained countdown, static under Reduce Motion.
- **Smart group-name suggestions:** suggest, never silently rename.
- **Display map placement:** spatial monitor diagram instead of a text-only picker.
- **Classic mechanical feedback:** tiny bevel press and optional haptic; no default sound.
- **Reconnect wave:** subtle stagger when a display returns, Reduce Motion aware.
- **Search upgrades:** fuzzy/initial matching, matched-range emphasis, `Cmd-1...9`,
  Shift-Return reveal.
- **Search aliases:** user/common shorthands such as `dl`, `icloud`, and provider names.
- **Running-app powers:** Quit/Hide and Option-click Hide Others where appropriate.
- **Versioned single-layout export envelope:** clear newer-version and portability errors.
- **Tab pulse on external change:** one-shot edge glow for a changed closed live drawer.
- **Dock-edge warning:** explain when `visibleFrame` shifts tabs around the Dock.
- **Modifier-hover Peek:** temporarily preview Notes/Fresh/Recents without keying search
  or entering edit mode.
- **Corner Store:** optional corner target whose quadrants route drops to favorites.

Intentional non-goals remain: process dock/app switcher, AppleScript dictionary,
free-floating off-edge placement, and default novelty sounds. iCloud sync remains a
separate future project.

## 7. Engineering, Documentation, and Verification

### Engineering/release cleanup

- Add a schema migration dispatch before version 2; version currently exists without
  migration routing.
- Test-host detection currently occurs after real Preferences/TabStore/DisplayRegistry
  initialization. Inject temporary/test services before construction so XCTest never
  reads live user state.
- Pin GitHub Actions and Homebrew tool versions where practical; scope `contents: write`
  to publish only; validate numeric release tags; run `hdiutil verify`.
- Clean trailing whitespace in `DrawerItem.swift`; give notes sizing independent
  constants instead of deriving from icon size; eventually rename drawer `autoHide` to
  `closeOnClickOutside` with Codable/UserDefaults migration to avoid concealment naming
  collision.
- Replace stale source-comment references to removed analysis IDs with durable PR links,
  or retain the completed index below.

### Documentation reconciliation

- Update PLAN's model for groups and current shipped features/non-goals.
- Correct first-run text: Apps plus Welcome, not one starter tab.
- Remove duplicated Folder prose and stale phase/post-v1 animation/import text.
- Align recovery text with automatic quarantine/backup behavior and future health UI.
- Correct Folder “read-only” language because drops move files into it.
- Stop claiming Settings `+` creates every tab kind until U2 lands.
- Explain exported JSON sensitivity: notes, bookmarks, URLs, usernames/paths, icon paths;
  bookmarks may not be portable.
- Reconcile root and `.github` CI/CD docs; explain `scripts/build.sh`'s external helper.

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
- Packaged app, Gatekeeper instructions, DMG verification, updater download.

## 8. Name Direction

`MacDring` is hard to parse aloud and describes lineage more than the product. The
replacement should suggest a physical place at the screen edge and remain broad enough
for apps, files, notes, disks, and URLs.

Ranked shortlist:

1. **Drawledge**: drawer + screen ledge; strongest product-specific character.
2. **Brimfold**: useful things folded into the screen's brim; polished and broad.
3. **ScreenSill**: clearest immediate meaning, less distinctive.
4. **Ledgelet**: light native-utility feel, slightly diminutive.
5. **Railnook**: friendly concealed place on a screen rail.
6. **Tabstead**: stable home for tabs; may sound browser-specific.
7. **Drawrail**: mechanically descriptive.
8. **Screenstead**: emphasizes dependable restore.
9. **Selvedge**: elegant “finished edge” metaphor; pronunciation/search need research.
10. **Corner Store**: delightful but implies only corners and is hard to own in search.

Current recommendation: **Drawledge: Edge drawers for your Mac**. Choose **Brimfold**
for a cleaner abstract brand or **ScreenSill** for maximum comprehension. Perform real
App Store, GitHub, package, domain, and trademark clearance before renaming. Avoid the
known crowded/colliding names listed in `sol.md` section 9.

## 9. Historical Index

The original B1-B12 parity work, later robustness/delight work through PR #84, and the
review set in PRs #85-#100 are merged. `fable-is-awesome.md` retains the detailed
FB/FP/FV/FU/FF/FI mapping and PR links; `awesome.md` retains earlier device/design
observations now consolidated above.
Notable merged batches include Trash, import/export, tab reorder/Move to Edge,
auto-hide/fade, Disks/Network/Cloud, per-tab behavior, custom icons, Recents/Fresh,
search, stable transient IDs, adaptive drawer chrome, status-menu tab access, and the
Welcome/checklist/delight batch.

Do not treat old “nothing P0-P1 remains” or “through PR #32” statements as current.
The active backlog in this file plus the implemented review index is the source of truth.
