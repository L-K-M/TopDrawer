# AGENTS.md

Guidance for AI coding agents working in the **Top Drawer** repository.

## What Top Drawer Is

Top Drawer is a fast, modern reimagining of the classic **DragThing**: colored
**tabs anchored to screen edges** that expand into **drawers** of apps, files,
folders, and URLs. It is multi-monitor aware and restores tab positions stably
across restarts. See `PLAN.md` for the full design, and `README.md` for the user
view.

## Tech Stack

- **Language:** Swift (Swift 5 language mode — `SWIFT_VERSION = 5.0`).
- **UI:** SwiftUI for the tab pill, drawer, and Settings content; AppKit for
  windowing (`NSPanel`, `NSStatusItem`, `NSVisualEffectView`).
- **System APIs:** `NSWorkspace` (launching), `CGDisplayCreateUUIDFromDisplayID`
  (stable display identity), Carbon `RegisterEventHotKey` (optional per-tab
  hotkeys — no Accessibility needed), `SMAppService` (launch at login).
- **Persistence:** a Codable `LauncherDocument` as JSON in
  `~/Library/Application Support/MacDring/launcher.json`; app-wide settings in
  `UserDefaults`.
- **Min target:** macOS 13 (Ventura). **Built with Xcode 16+** (uses
  `UnevenRoundedRectangle`, `SMAppService`, file-system-synchronized groups).
- **App type:** menu-bar agent (`LSUIElement = true`, `.accessory` policy, no
  Dock icon).

## Build & Run

The Xcode project uses **file-system-synchronized groups**, so new files added
under `MacDring/` or `MacDringTests/` are picked up automatically — no
`project.pbxproj` edits needed.

```bash
# Build
xcodebuild -project MacDring.xcodeproj -scheme MacDring -configuration Debug build

# Run unit tests (pure logic: layout, anchors, Codable, bookmarks, store, prefs)
xcodebuild -project MacDring.xcodeproj -scheme MacDring -destination 'platform=macOS' test
```

Prefer building/running from Xcode during development so window behavior and the
menu-bar item appear in a real GUI session.

The Linux port builds with SwiftPM only: `swift build` at the root (the shared core,
target `MacDring`) and `swift build --package-path linux` (daemon + shell). Its tests,
the `.deb` packaging (`linux/packaging/build-deb.sh`), and the D-Bus interface are
documented in `linux/README.md`; the release workflow attaches the `.deb` to each
GitHub Release.

The app icon is derived from the master artwork `Tools/AppIcon-source.png`
(an open wooden drawer of glowing app tiles). `Tools/README.md` documents how
the `AppIcon.appiconset` slots are regenerated from it.

## Module Layout

Mirrors `PLAN.md §11`. Keep modules aligned:

- `Model/` — Codable model (`Tab`, `DrawerItem`, `ScreenAnchor`, `Edge`,
  `TabGlyph`, `TabBehavior`, `HotkeySpec`, `IconStyle`, `LauncherDocument`),
  `ColorHex`, `Preferences`, and the small UI enums in `PreferenceEnums.swift`.
- `Store/` — `TabStore` (JSON load/save), `RecentsStore` (recent-items history),
  `BookmarkResolver`, and the live transient listers (`FolderLister`, `DisksLister`,
  `NetworkLister`, `CloudLister`, `RecentsLister`, `FreshLister`). `SpotlightQuery`
  wraps `NSMetadataQuery` — the one **async** lister, backing the Fresh tab and the
  system source of Recents (reads the Spotlight index only; no special permission).
- `Screens/` — `DisplayRegistry` (UUID mapping) and the pure `EdgeLayout` math.
- `Tabs/` — `TabController` (the orchestrator), `TabWindowController`,
  `TabStripView` (modern pill / classic folder tab; vertical side labels),
  `TabStripModel`.
- `Drawer/` — `DrawerWindowController` (incl. `DrawerHostingView`, the AppKit
  `NSDraggingDestination` that handles spring-loaded per-slot file drops),
  `DrawerView`, `DrawerModel`, `ItemView`, and `DrawerSearch` (pure type-to-find
  filter / selection / key-classification helpers).
- `Launch/` — `ItemLauncher`. `Hotkeys/` — `CarbonHotkey`, `KeyCodes`.
- `Settings/` — the SwiftUI settings window and panes, plus the small modal
  windows (`NewTabView`/Controller, `IconEditorView`/Controller).
- `Common/` — `VisualEffectView`; `TabShapes` (`edgeRoundedRect` for the
  inward-rounded/edge-sharp tab pill + drawer, and `ClassicTabShape`);
  `ActivationPolicy` (the shared `.regular`↔`.accessory` revert guard);
  `IconRenderer` (draws an `IconStyle` to an `NSImage`).
- `Notes/` — the notes tab's editor. `NotesEditorBridge` (the wire protocol and its
  JavaScript encoding) and `NotesEditorHostSession` (the host-side reconciler that
  decides *when* the editor is told about a document) are Foundation-only and run on
  both platforms' test jobs; `NotesEditorWebView` (WKWebView adapter),
  `NotesEditorSchemeHandler` (serves the bundled assets over a custom scheme),
  `NotesEditorMessageProxy` and `NotesEditorPane` are macOS-only. The editor itself
  is the bundled web asset in `EditorWeb/`, copied into the app by a build phase.

## Conventions

- Follow the Swift API Design Guidelines.
- One type per file; file name matches the primary type. (Small exceptions:
  `PreferenceEnums.swift` groups four related UI enums; `DrawerItem.swift`
  carries its `fromFileURL`/`fromLink` factory extension.)
- Use `// MARK:` to organize sections.
- Avoid force-unwraps outside tests.
- Keep `EdgeLayout` **pure** (no global state, no AppKit beyond `CGGeometry`) so
  it stays unit-testable — it's the geometry backbone.

## Dependencies

Exactly one: [`PictKit`](https://github.com/L-K-M/Pict), a first-party SwiftPM
package holding the shared icon store and resolution ladder that Zap, Jetty and
the Pict editor also use. Top Drawer **reads** it and writes nothing — editing
lives in Pict, which needs no permissions and can be sandboxed.

Icon precedence in `ItemView.resolveIcon`, top rung first:

1. the item's `customIconBookmark` (an image file) — unchanged
2. the item's `iconStyle` (a generated folder/tile) — unchanged
3. the shared store — an icon set in Pict, Zap or Jetty
4. the target's own un-masked bundle artwork
5. the kind-specific default (drive, cloud, favicon, Trash, `NSWorkspace`)

Rungs 1 and 2 staying on top is what makes this invisible on upgrade, and it is
also a feature: two items pointing at one app are allowed to differ.

## Critical Constraints

- **No scary permissions for core features.** Launching uses `NSWorkspace`.
  Per-tab hotkeys use Carbon `RegisterEventHotKey` (no Accessibility). The
  click-outside dismiss uses a global **mouse** monitor (allowed without
  permission) and a **local** key monitor for Esc. **Never** add a *global key*
  monitor or a `CGEventTap` — that would require Accessibility/Input Monitoring
  and break the "no-permission" promise.
- **Tabs and drawers must stay non-activating** (`NSPanel` with
  `.nonactivatingPanel`). Clicking a tab or launching an item must never steal
  focus from the user's frontmost app.
- **Stable restore is sacred.** Persist a tab's location as a display **UUID** +
  **edge** + **fractional position** — never raw pixel coordinates. All on-screen
  placement goes through `EdgeLayout` against `NSScreen.visibleFrame`.
- **Show on every Space / over fullscreen:** keep `collectionBehavior` =
  `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` on tab/drawer panels.
- **Keep `LSUIElement = true`** (no Dock icon); Settings temporarily switches to
  `.regular` and back to `.accessory` on close.

## Testing Notes

- Unit-test pure logic: `EdgeLayout` geometry, `ScreenAnchor` clamping/coding,
  `LauncherDocument`/`DrawerItem` Codable + forward-compat, `BookmarkResolver`,
  `TabStore` load/save/mutations, `Preferences` defaults/clamping.
- `AppDelegate.applicationDidFinishLaunching` is guarded by `isRunningTests`, so
  the test host doesn't spin up windows.
- Window placement, multi-monitor, Spaces, fullscreen, drag-to-reposition, and
  drag-and-drop need a **real GUI session** and are verified manually.
- **When `xcodebuild` hangs** at the `clang -v -E -dM` probe (a known Xcode 26.5
  `SWBBuildService` deadlock — see `PLAN.md §12`), you can still: **type-check** the
  whole module with `xcrun --sdk macosx swiftc -typecheck -target arm64-apple-macos13.0
  $(find Top Drawer -name '*.swift')`, and **regenerate the app icon** with `swift
  Tools/GenerateAppIcon.swift` — both invoke the compiler directly and don't touch the
  wedged build service. Fix the build service with `sudo xcodebuild -runFirstLaunch`.

## AI review scope

GLM review defaults to **hybrid**: the first review is full, then follow-ups
review changes since the last completed review plus a rotating sample of older
PR changes. Keep hybrid for normal implementation/fix cycles.

Before the next review-triggering push, apply at most one override label:

- `zai-review:full` for high-risk changes, force-push recovery, or a deliberate
  final deep audit.
- `zai-review:hybrid` to explicitly select the normal delta-plus-audit mode.
- `zai-review:incremental` only for low-risk, latency-sensitive follow-ups
  after a completed full review; this omits the rotating old-code audit.

Labels select the next run but do not trigger one themselves. Remove an override
to return to hybrid. Missing/incomplete state and non-ancestor history safely
fall back to a full review.

## Do / Don't

- **Do** update `PLAN.md` when the design changes, and keep `README.md` in sync.
- **Do** keep file/folder items working via bookmarks; render broken items
  dimmed rather than dropping them.
- **Do** assume Developer ID + notarization (not the App Store) for v1; the
  sandbox/security-scoped-bookmark path is a documented future change.
- **Don't** add heavy dependencies; prefer system frameworks.
- **Don't** persist absolute window frames, or let a tab/drawer activate the app.
- **Don't** rely on SwiftUI `.onDrop` for drops *into the drawer* — its callbacks
  fire unreliably in the borderless panel (more so nested in a `ScrollView`) and give
  no hovered location. For **internal reorder** use a `DragGesture` + reported cell
  frames; for **external file drops** use the AppKit `NSDraggingDestination` on the
  drawer's hosting view (`DrawerHostingView`), mapping the converted drag location to
  a slot via `DrawerModel.slotFrames`. (The tab *pill* still uses `.onDrop` — that one
  works, and it's only used to add-to-tab / trigger the spring-open hover.)

<!-- shared-rules:start -->

## Working practices

- Follow explicit task instructions over the default workflow below.
- Before editing, inspect the branch and working tree, fetch remote updates,
  and fast-forward where safe. Never overwrite existing work to update.
- Resolve ambiguity before making consequential changes. State low-risk
  assumptions; ask when scope, safety, or expected behavior is unclear.
- Keep changes focused. Do not modify unrelated code, formatting, or comments.
- Prefer surgical edits over whole-file rewrites when the result is equivalent.
- Stage only intended files. Inspect the diff before committing.

## Communication

- Be concise, factual, and direct. Preserve necessary context and uncertainty.
- Avoid praise, motivational filler, emojis, and em dashes in new prose.
- Address the reader directly in user-facing copy.
- Report what was verified and what remains unverified. Never imply that an
  unavailable check passed.

## Code design

- Prefer early returns and shallow nesting. Separate logical blocks with
  blank lines.
- Use descriptive constants or enums for meaningful or repeated values.
  Use existing standard definitions for protocol/specification constants.
  Keep obvious, one-off values inline.
- Use enums for behavioral modes that would otherwise require ambiguous
  boolean arguments.
- Default members to private. Widen visibility only for required consumers,
  and review the change as an API design decision.
- Follow the repository's declared dependency boundaries. UI and controllers
  must use application services rather than directly accessing databases,
  subprocesses, sockets, or other low-level mechanisms.
- Encapsulate low-level mechanics behind domain-oriented interfaces.
- Reuse genuinely shared logic. Avoid speculative abstractions and layers
  that only forward calls.
- Prefer pure functions for business rules and immutable data where practical.
  Isolate side effects; document non-obvious state ownership or synchronization.
- Explain non-obvious intent, constraints, and tradeoffs in comments.
  Do not narrate obvious code. Add examples or diagrams when they clarify it.

## Validation and errors

- Validate untrusted input at entry points. Where practical, represent valid
  states in types and enforce persistent invariants in database schemas.
- Represent absence and failure explicitly.
- Use assertions for internal programming invariants, not external-input
  validation or required runtime error handling.
- Prefer explicit, actionable errors over silent failure or undocumented
  fallback. Document intentional recovery behavior.
- Never report a skipped or failed operation as successful.

## Bug fixes

1. Identify the root cause and define an observable success criterion.
2. Add a regression test and observe the relevant failure before fixing it.
3. Implement the fix and observe the test passing.
4. Check surrounding behavior for regressions and architectural consistency.

If an automated regression test is impractical, document the reproduction
and verification procedure. State any inability to reproduce the failure.

## Verification

- Run relevant tests and lint after changes.
- Choose coverage by affected behavior and risk, not patch size.
- Use integration or end-to-end tests for critical workflows and boundaries;
  test isolated business rules at the lowest effective level.
- Run broader suites for cross-cutting or high-risk changes, and the full
  required release checks before releasing.
- Validate the requested command, options, platform, and configuration.
  Unrelated green CI is not proof that the reported problem is fixed.
- Recheck after the final edit. Distinguish local checks from CI results.

## Commit messages

- Use a capitalized, imperative subject without a final period.
- Target 50 characters; never exceed 72.
- Separate the subject and body with one blank line.
- Wrap body text at 72 characters.
- Explain what changed and why. Leave implementation mechanics to the code.

## Implementation and review

Unless explicitly instructed otherwise:

1. Work on a focused branch and open a PR against main.
2. Inspect CI results and completed review feedback for the latest commit.
   A successful reviewer job does not mean the review found no problems.
3. Address important findings or explain why they do not apply. Handle minor
   findings according to the stopping rules below.
4. Evaluate each fix in the surrounding project, add regression coverage,
   and rerun affected checks before pushing.
5. Repeat until a stopping criterion is met.
6. Merge without asking again once the stopping criterion is met, required
   checks pass on the latest commit, and no unresolved blockers or required
   human review requests remain.

### Automated review stopping rules

Judge findings by verified impact, not the reviewer's severity label.
Important findings concern correctness, security, data loss, broken builds,
or materially degraded behavior/performance.

Track completed review rounds and consecutive rounds without important
findings. Reruns of the same revision and integration failures do not count.

- No applicable actionable feedback: finish immediately.
- First minor-only round: optionally fix worthwhile, low-risk findings.
  Do not manufacture another push merely to obtain another review.
- Two consecutive rounds without important findings: stop responding to
  automated nitpicks, even if actionable minor suggestions remain.
  Defer worthwhile leftovers rather than continuing the cycle.
- A confirmed important finding resets the minor-only streak. Address it
  and verify the fix before continuing.

After ten completed rounds, enter stabilization:

- Stop optional cleanup, refactoring, and nitpick fixes.
- One completed review without confirmed important findings is sufficient
  to finish, even if minor suggestions remain.
- Continue only for confirmed important defects. If resolving them stalls,
  report the blockers rather than continuing indefinitely.

These limits end optional automated-feedback work. They do not waive
confirmed blockers, unresolved human review requests, or required checks.

### Reviewer integration failures

After two consecutive reviewer-integration failures, stop and report the
review gap. Do not treat failures as approval. An explicit user instruction
may waive review; report that waiver rather than claiming review passed.

## Completion checklist

- The requested behavior is implemented without unrelated changes.
- Relevant checks pass for the latest code.
- Important review findings are addressed or rejected with reasons.
- Deferred suggestions, remaining risks, and validation gaps are disclosed.
- The final response accurately states whether work is committed, pushed,
  and merged.

<!-- shared-rules:end -->
