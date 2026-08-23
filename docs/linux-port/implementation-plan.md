# Linux Port — Implementation Plan (executor edition)

*Written 2026-08-23. This is the step-by-step execution plan for the Ubuntu port
research in this directory. It is written for an AI coding agent of moderate
capability ("the executor") working autonomously in a Linux environment: it
front-loads decisions, names files, and prefers boring, verifiable techniques over
clever ones. Read [`README.md`](README.md) first for the big picture; each work item
below links the research doc that explains its *why*.*

---

## Part 0 — Ground rules (apply to every work item)

### 0.1 The shape of the work

The port ships as a sequence of **small pull requests** (IDs `LP-01` … `LP-36`,
defined in Parts 1–9 below), across two repositories (`L-K-M/TopDrawer` and
`L-K-M/Pict`), **in LP-number order**. **One PR at a time**: implement → open PR →
babysit reviews to steady state → merge → only then start the next. Never work
ahead on unmerged foundations. (One deliberate exception: LP-24 is two PRs, Pict
first — see that item.)

### 0.2 Environment

- You are on **Linux**. You can build and test everything Linux-side locally.
  You **cannot build macOS code locally** — the repos' existing macOS CI
  (`.github/workflows/ci.yml`, `xcodebuild` on a macOS runner) is your only macOS
  validation. Treat a green macOS CI job as a merge requirement on every PR that
  touches shared files.
- Swift toolchain: check `swift --version` first. If absent, install via
  [swiftly](https://www.swift.org/install/linux/) (Ubuntu 24.04 toolchain). If
  that fails, develop "CI-driven": push and let the Linux CI job be your compiler
  (slow and noisy — prefer a local toolchain). The official `swift:6.3-noble`
  Docker image is a third option only where Docker is actually available in your
  environment.
- System packages you will need at various points (install with `apt-get`):
  `libgtk-4-dev`, `libwebkitgtk-6.0-dev`, `librsvg2-bin`, `libglib2.0-bin` (gio
  CLI), gtk4-layer-shell dev package (see the note in LP-20 — verify the exact
  package name for your Ubuntu version), `dbus` (session bus for tests).

### 0.3 Keep macOS green — the prime directive

Most early PRs touch files that the Mac apps compile. Rules:

- **Never change macOS behavior.** Extractions are *pure moves*; guards are
  additive (`#if` around existing code, never rewrites of it).
- Every PR's body states which existing macOS tests cover the touched code.
- If macOS CI fails on your PR, fixing it is your top priority — re-read the diff
  adversarially, fix, and repush. Never merge with red CI on either platform.

### 0.4 Standard cross-platform idioms (use these, not inventions)

```swift
// CG value types (CGRect/CGPoint/CGSize/CGFloat) — they live in Foundation on Linux:
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

// Crypto:
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto            // swift-crypto — identical SHA256 API
#endif

// Networking:
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Whole-file guard for macOS-only files that must stay inside a shared target:
#if canImport(AppKit)
... entire existing file body, unchanged ...
#endif
```

- Platform-conditional package dependency (works from swift-tools 5.3+):
  `.product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))`
- Platform-dependent source lists: `Package.swift` is Swift — `#if os(Linux)` in the
  manifest is evaluated on the build host, so a target can compile a curated
  `sources:` list on Linux and (by omitting `sources:`) everything on macOS.
  Files in the target `path` that are not listed are simply not compiled.
- **Module naming matters:** the TopDrawer SwiftPM target must be named `MacDring`
  and the test target `MacDringTests`, so the existing `@testable import MacDring`
  test files compile unmodified on Linux.

### 0.5 Weak-model doctrine: prefer boring mechanisms

Wherever the research offers a choice, this plan has already chosen the *most
verifiable* option:

- **Parse files and call CLIs before writing C interop.** `/proc/self/mounts`,
  `recently-used.xbel`, `.desktop` files, XDG trash directories are plain text —
  parse them in Swift. `gio trash/--empty/launch/open`, `udisksctl`,
  `rsvg-convert`, `xdg-open`, `xdg-mime` are stable CLIs — shell out via `Process`.
- **Pure Swift before C libraries** for raster work (PNG codec package + hand-rolled
  pixel ops) — see LP-04.
- **C interop only where unavoidable**: GTK4 + gtk4-layer-shell + WebKitGTK
  (LP-20+, LP-36). Those PRs contain exact recipes and name shipped Swift apps to
  copy from.
- When you must deviate from this plan (a package is missing, an API moved), consult
  the research docs in this directory, pick the smallest deviation, and record it in
  the PR body under a "Deviation from plan" heading.

### 0.6 PR lifecycle protocol (every LP item)

1. **Sync**: `git fetch origin main && git checkout -B claude/lp-<nn>-<slug> origin/main`
   in the right repo.
2. **Implement** exactly the item's scope. Target diff size < ~600 changed lines
   excluding tests and lockfiles; if you blow past it, stop and split (open the
   first coherent half).
3. **Validate locally**: run the item's Acceptance commands. For shared-file PRs,
   also re-read your diff asking "what would make `xcodebuild` reject this?"
4. **Push** `git push -u origin <branch>` (retry with backoff on network errors).
5. **Open the PR** titled `[LP-<nn>] <item title>`, ready for review (not draft).
   Body: goal (one paragraph), what changed, how it was validated, link to this
   plan's section, any deviations. Check for a PR template first and follow it if
   one exists.
6. **Subscribe and arm**: `subscribe_pr_activity` on the PR; arm a `send_later`
   self check-in one hour out — **`send_later` is one-shot, so the first action of
   every check-in is re-arming the next one** (the "hourly" cadence exists only if
   you keep re-arming). These repos have an automated reviewer
   (`zai-code-review`) that posts rounds on PR activity on its own; additionally
   request a review via any available mechanism (e.g. `request_copilot_review`)
   now and after every substantive push, so the round counter keeps meaning.
7. **Babysit** per the repo's `CLAUDE.md` policy: triage every comment into
   apply / decline-with-recorded-reasons / refute-with-evidence; verify factual
   claims against the code or docs before acting; keep a running declined list;
   never flip-flop. Drive CI to green as part of every round.
8. **Steady state** is reached when ANY of:
   - two consecutive review rounds yield no valid, actionable findings;
   - two consecutive hourly check-ins pass with **no new review activity at all**
     (the "two timeouts" case);
   - the reviewer re-raises items already declined with reasons, or contradicts
     its own earlier feedback;
   - everything remaining is out of scope (collect as follow-ups in the chat log).
   **Exception — humans:** comments from human reviewers are never timed out or
   steady-stated away. An unresolved human "changes requested" blocks the merge;
   address it, and if the human is unresponsive, ask the user instead of merging.
9. **Merge**. Preconditions, all required:
   - Both platform CI jobs are **completed green on the current head SHA** — a
     pending check defers the merge to the next check-in; a check that stays red
     for reasons you've established are infrastructure (per the CI-red rules)
     across 3+ check-ins → ask the user.
   - **Immediately before merging, re-fetch the PR's comments and reviews.** A
     new human comment cancels the merge and re-enters babysitting; new automated
     rounds after steady state are ignorable per the repo policy.
   Then: post a short scorecard in chat (what was real, refuted, deferred), merge
   with a **merge commit** (matches both repos' history), delete the branch,
   `unsubscribe_pr_activity`, and delete the pending self check-in trigger for
   that PR. (A human comment arriving *after* the merge won't be pushed to you —
   that is accepted; the user reads the repo.) If the merge is rejected (branch
   protection, required reviews), report to the user and wait — do not force
   anything.
   *Note on authority:* the repos' `CLAUDE.md` babysitting policy stops at
   declaring a PR "merge-ready"; this step deliberately extends it — the executor
   prompt grants standing authorization to perform the merge at steady state.
10. **Advance**: one-line completion note in chat; start the next LP item.

### 0.7 Resumability

PR titles carry the stable IDs. To find where the effort stands (e.g. after a fresh
session): list merged PRs matching `[LP-` in both repos; the next item is the
lowest-numbered ID not yet merged. An **open** unmerged `[LP-…]` PR means resume its
babysitting loop, not restart it.

### 0.8 When to stop and ask the user

Only for: branch-protection/merge failures; an unresolved human review; a plan
assumption that collapses in a way this plan doesn't cover (record what you tried);
credentials/network problems you cannot route around; or any action that would be
destructive or outward-facing beyond opening/merging these PRs. Everything else:
decide, record, proceed.

---

## Part 1 — Foundations (CI first, so every later PR has a net)

### LP-01 · Pict · PictKit compiles and tests on Linux + Linux CI
**Branch** `claude/lp-01-linux-ci` · **Size** S-M · **Why**: [06](06-pict-port.md), [03](03-swift-on-linux.md)

- In `Package.swift` (keep the existing swift-tools version), give the `PictKit`
  target a Linux-only curated `sources:` list (`#if os(Linux)`); same for
  `PictKitTests`. Lists (dependency-closure-checked against the sources on
  2026-08-23; still verify by compiling, and record any trim/extension):
  - Sources: `Store/IconEntry.swift`, `Store/IconEntryKey.swift`,
    `Store/IconStoreLocation.swift`, `Store/IconStore.swift` **with guards**
    (CG import guard on line 1; `#if canImport(CoreGraphics)` around exactly its
    two CG members, `image(for:)` and `setIcon(_:for:...)` — the rest of the file
    is pure Foundation and is required by `IconEntry.imageExtensions` references
    and by `ZapManifestImport`), `Migration/ZapManifestImport.swift`,
    `Resolve/IconSourceMode.swift`.
    Do **not** include `Resolve/IconRenderOptions.swift` here — its `plain()`
    calls `IconBitmap.pixelSize`, which doesn't reach Linux until LP-03 (it moves
    into the list there).
  - Tests: `IconEntryKeyTests.swift`, `ZapManifestImportTests.swift` (the latter
    drives the non-CG half of `IconStore` directly — covered by the guarded
    file). `IconTestSupport.swift` stays out (it is CoreGraphics top to bottom).
- Add `.github/workflows/linux-ci.yml`: on PRs and pushes to main, a job with
  `container: swift:6.3-noble` running `swift build && swift test`. (If actions
  in a container need it, set `git config --global --add safe.directory
  "$GITHUB_WORKSPACE"` before checkout-dependent steps.)
- **Acceptance**: Linux job green with both suites running; existing macOS CI
  untouched and green; zero diff to macOS-compiled source semantics (guards only).
- **Pitfalls**: don't reformat files while adding guards; `IconEntryKey`'s
  `Bundle(url:)` line compiles on Linux (corelibs has Bundle) — leave it alone.

### LP-02 · TopDrawer · Root `Package.swift` + Linux CI for the pure core
**Branch** `claude/lp-02-linux-ci` · **Size** M · **Why**: [05](05-topdrawer-port.md) §buckets

- Add a **root `Package.swift`** (this does not disturb `MacDring.xcodeproj`;
  macOS CI keeps using `xcodebuild -project`): target **named `MacDring`**
  (module name must match the tests' `@testable import MacDring`), `path:
  "MacDring"`, with an explicit `sources:` list (use it on both platforms — this
  package exists for Linux; macOS keeps building through Xcode). Test target
  `MacDringTests`, `path: "MacDringTests"`, curated `sources:`.
- Dependency: `swift-crypto`, product condition `.when(platforms: [.linux])`;
  apply the CryptoKit guard idiom in `Model/DrawerItem.swift` and guard its
  `trash()` factory's `.trashDirectory` use with `#if os(macOS)` (Linux path:
  `~/.local/share/Trash/files` — see [03](03-swift-on-linux.md)).
- Sources list (dependency-closure-checked 2026-08-23; still verify by compiling):
  all of `Model/` except `ColorHex.swift` and `Preferences.swift` —
  **`PreferenceEnums.swift` IS included, with guards**: `#if canImport(AppKit)`
  around its AppKit import and around `TabWindowLevel`'s two `NSWindow.Level`
  computed properties (required: `Tab.swift`, `TabKind.swift`, and
  `DrawerMetrics.swift` all use `DrawerLayout`, which lives in this file);
  **`Store/BookmarkResolver.swift` with guards**: `#if os(macOS)` around the
  bodies of `makeBookmark`/`resolve` (Linux: return `nil` — every caller already
  falls back to the plain URL; the bookmark APIs are Darwin-only) — required by
  `DrawerItem.swift`;
  `Screens/EdgeLayout.swift` and `Drawer/DrawerMetrics.swift` (CG import guard);
  `Drawer/DrawerSearch.swift`, `Drawer/ExternalDropTarget.swift`,
  `Tabs/DrawerLaunchRequest.swift`, `Common/TimeBucket.swift`,
  `Updates/SemanticVersion.swift`, `Updates/GitHubRelease.swift`.
- Starting tests list: `EdgeLayoutTests`, `ScreenAnchorTests`,
  `LauncherDocumentCodableTests`, `LenientDecodingTests`, `TabBehaviorTests`,
  `DrawerItemTests`, `DrawerGroupingTests`, `DrawerMetricsTests`,
  `DrawerSearchTests`, `DrawerLaunchRequestTests`, `ExternalDropTargetTests`,
  `TimeBucketTests`, `SemanticVersionTests`, `GitHubReleaseTests`.
- Same `linux-ci.yml` shape as LP-01.
- **Acceptance**: `swift test` green on Linux with those suites; macOS CI green;
  `.xcodeproj` untouched.
- **Pitfalls**: file-system-synchronized Xcode groups mean any *new* Swift file
  under `MacDring/` enters the macOS build — new Linux-only files in this package
  must either live outside `MacDring/` or carry `#if !canImport(AppKit)` /
  `#if os(Linux)` whole-file guards. Prefer the guards; keep new files minimal here.

---

## Part 2 — PictKit portability (the seams of [06](06-pict-port.md))

### LP-03 · Pict · `PixelImage` + codec seam; artwork math on Linux
**Branch** `claude/lp-03-pixelimage-seam` · **Size** M

- New file `Sources/PictKit/Artwork/PixelImage.swift`: `struct PixelImage { var
  width: Int; var height: Int; var samples: [UInt8] /* RGBA8, premultiplied,
  row-major */ }` plus a small `IconCodec` protocol: `decode(URL) -> PixelImage?`,
  `decode(Data) -> PixelImage?`, `encodePNG(PixelImage, to: URL) throws`.
- Bridge on macOS only (`#if canImport(CoreGraphics)`): `PixelImage(cgImage:)` and
  `makeCGImage()` — reuse the sampling code already in `AlphaMask.init(image:)` /
  `IconBitmap.makeContext`.
- Add `AlphaMask.init?(pixelImage:longestEdge:)` routed through the existing pure
  `init(width:height:samples:)`; add `PixelImage`-based overloads next to the
  `CGImage` ones in `IconShapeClassifier`; leave all CG entry points untouched.
- Extend the Linux sources list with: `Artwork/AlphaMask.swift`,
  `Artwork/IconShapeClassifier.swift`, `Artwork/IconNormalizer.swift`,
  `Artwork/IconImageValidator.swift`, `Artwork/IconBitmap.swift`, and
  `Resolve/IconRenderOptions.swift` (deferred from LP-01 — its `plain()` needs
  `IconBitmap.pixelSize`) — guarding each file's CG-touching members with
  `#if canImport(CoreGraphics)` so the pure math (`layout()`, `check()`,
  thresholds, `pixelSize`) compiles everywhere.
- Tests on Linux: the synthetic-mask classifier suite, `IconNormalizerTests`'
  `layout()` tests, `IconImageValidatorTests`' `check()` table, `IconBitmapTests`'
  `pixelSize` tests.
- **Acceptance**: Linux suites green; macOS green with zero behavioral diff.

### LP-04 · Pict · Pure-Swift raster backend for Linux
**Branch** `claude/lp-04-raster-backend` · **Size** M-L

- Add **`tayloraswift/swift-png`** (`from: "4.5.0"`, product `PNG` — vetted in
  Part 10, incl. the exact decode/encode API and the premultiplied↔straight alpha
  conversion requirement) conditioned `.when(platforms: [.linux])`, and implement
  `IconCodec` with it (`Sources/PictKit/Artwork/LinuxCodec.swift`, whole-file
  `#if os(Linux)`).
- Implement pure pixel ops on `PixelImage` (new file, platform-neutral, unit-tested
  against the *existing* expectations):
  - `downsample(longestEdge:)` — area-averaging; never upscale (mirror
    `IconBitmap.downsample` semantics).
  - `maskingCorners(radiusFraction:)` — per-pixel alpha multiply by rounded-rect
    coverage (antialias by 4× supersampling the coverage at edges).
  - `shadow(...)` for `IconNormalizer.render` — gaussian approximated by three
    box blurs of the alpha channel; **negative-y-is-down convention must match**
    the CG implementation — port
    `testShadowFallsBelow…` (the asymmetry test) first and make it pass.
- Route `IconNormalizer.normalize`/`render` and `IconBitmap` through the seam so
  each has a CG path (macOS, unchanged) and a PixelImage path (both platforms;
  on macOS it's exercised only by tests).
- **Acceptance**: classifier/normalizer/validator/bitmap test suites green on
  Linux via the seam fixtures (`IconTestSupport` gets a `PixelImage`-based
  `makeImage`/`writePNG`); macOS green.
- **Pitfalls**: premultiplied vs straight alpha — `PixelImage` is premultiplied;
  encode/decode must convert correctly (PNG is straight alpha). Write a
  round-trip test.

### LP-05 · Pict · IconStore + watcher on Linux
**Branch** `claude/lp-05-store-linux` · **Size** M

- `IconStore` (already in the Linux list since LP-01 with its two CG members
  guarded out): this PR brings the image path to Linux — route those two methods
  through the codec seam (`PixelImage`-typed core implementations; the `CGImage`
  signatures become macOS-only convenience overloads under
  `#if canImport(CoreGraphics)`), and remove the LP-01 guards that are thereby
  superseded.
- `IconStoreWatcher`: keep the FSEvents implementation under
  `#if canImport(CoreServices)` (whole-body); add a Linux implementation in the
  same file (or a sibling `#if os(Linux)` file) using **inotify via Glibc**:
  `inotify_init1(IN_NONBLOCK|IN_CLOEXEC)`; watch the entries directory for
  `IN_CREATE|IN_MOVED_TO|IN_DELETE|IN_CLOSE_WRITE`; drain events with a
  `DispatchSource.makeReadSource` on the fd (read sources exist on Linux);
  debounce 0.2 s; reload-then-notify on main queue (same contract). Two required
  behaviors from [06](06-pict-port.md): tolerate self-notification (macOS used
  `IgnoreSelf`; on Linux an extra reload after own writes is acceptable — do NOT
  try to be clever), and if the directory doesn't exist yet, watch the parent
  until it appears.
- **Acceptance**: `IconStoreTests` green on Linux (swap only the CG fixture for a
  PixelImage one); a new Linux-only watcher test (write a file into a temp store
  from the test process, expect `onChange`); macOS green.

### LP-06 · Pict · Resolver + status + PictURL portable; PictKit fully compiles on Linux
**Branch** `claude/lp-06-resolver-linux` · **Size** M

- `IconResolver`: introduce a platform image alias — `public typealias
  ResolvedIconImage = NSImage` on macOS, and on Linux a tiny
  `public struct ResolvedIconImage { public let pixels: PixelImage; public let
  pointSize: Double }` — constructed in the one place `resolve()` builds its
  output today. Public API shape otherwise unchanged.
- New protocol `ArtworkProviding { func artwork(for target: IconTarget) ->
  PixelImage? }`; `BundleArtwork` conforms on macOS (whole-file
  `#if canImport(AppKit)` stays); Linux gets a placeholder conformance returning
  `nil` (real icon-theme lookup arrives in LP-24). `IconArtworkStatus` consumes
  the protocol.
- `PictURL`: guard the two `NSWorkspace` calls; Linux impls: installed-probe =
  `xdg-mime query default x-scheme-handler/pict` non-empty; open = `xdg-open`.
- Remove the Linux `sources:` curation for PictKit **entirely** — from this PR on,
  the whole PictKit target must compile on Linux (files that are macOS-only keep
  whole-file guards). This is the milestone check.
- **Acceptance**: `swift build && swift test` green on Linux with no curated list;
  `IconResolverTests` green on Linux (needs a drained main queue — run loop spin
  in tests); macOS green.

---

## Part 3 — TopDrawer core extraction (macOS-improving; validated by macOS CI)

### LP-07 · TopDrawer · Combine-compat shim + stores/prefs on Linux
**Branch** `claude/lp-07-combine-shim` · **Size** M

- New `MacDring/Common/ObservationCompat.swift` (guarded `#if !canImport(Combine)`):
  minimal `ObservableObject` protocol with `objectWillChange`, a `@Published`
  property wrapper, and an `ObservableObjectPublisher` with `send()` and a
  `sink(receiveValue:) -> AnyCancellable` sufficient for the two
  `objectWillChange.sink` uses in `TabStoreTests`. Keep it ~100 lines; fidelity
  beyond what the shared code uses is out of scope. **Two traps, both mandatory to
  handle** (a naive shim makes the sink-count tests silently observe zero
  events): (1) `objectWillChange` must be **per-object-stable** — back the
  protocol-extension default with a locked `[ObjectIdentifier:
  ObservableObjectPublisher]` registry, never a fresh publisher per access;
  (2) `@Published` must reach the enclosing object's publisher — use the
  `static subscript(_enclosingInstance:wrapped:storage:)` property-wrapper
  feature (available on Linux).
- **Wrap the bare `import Combine` lines in `#if canImport(Combine)`** — the shim
  provides types inside the `MacDring` module, not a module named `Combine`. The
  five files: `Store/TabStore.swift`, `Store/RecentsStore.swift`,
  `Drawer/DrawerModel.swift`, `Tabs/TabStripModel.swift`, and
  `MacDringTests/TabStoreTests.swift`.
- Guard the AppKit/SwiftUI/ServiceManagement corners of `Model/Preferences.swift`
  (login-item + NSColor validation) with `#if canImport(AppKit)` /
  `#if canImport(ServiceManagement)`. (`PreferenceEnums.swift` was already
  guarded and listed in LP-02.)
- Linux sources gain: `Store/TabStore.swift`, `Store/RecentsStore.swift`,
  `Store/FolderLister.swift`, `Model/Preferences.swift`,
  `Drawer/DrawerModel.swift` (drop its AppKit import — verified unused beyond CG
  types), `Tabs/TabStripModel.swift`.
  Tests gain: `TabStoreTests`, `RecentsStoreTests`, `RecentsListerTests` (if it
  compiles without the Spotlight type — else LP-08), `FolderListerTests`,
  `PreferencesTests`, `DrawerModelTests`.
- **Acceptance**: those suites green on Linux — `TabStoreTests` (67 tests) green
  is the milestone; macOS CI green (macOS code path is untouched: it still uses
  real Combine).

### LP-08 · TopDrawer · Recents/Fresh seam (`RecentFilesQuerying`)
**Branch** `claude/lp-08-recents-seam` · **Size** S-M

- Extract `SpotlightQuery.Result` and `SpotlightQuery.Mode` into a new
  platform-neutral file (e.g. `Store/RecentFilesQuery.swift`) as top-level types
  (`RecentFileHit`, `RecentQueryMode`) with `typealias`es preserving the old
  names on macOS so nothing else changes; define
  `protocol RecentFilesQuerying { func start(mode:scopes:limit:completion:); func
  cancel(); var isGathering: Bool }`; make `SpotlightQuery` conform (its file
  keeps a whole-body `#if os(macOS)` guard).
- Linux sources gain: the new file, `Store/FreshLister.swift`,
  `Store/RecentsLister.swift`, `Store/FreshScanner.swift`. Tests:
  `FreshListerTests`, `FreshScannerTests`, `RecentsListerTests`.
- **Acceptance**: suites green on Linux; macOS green with zero behavior change
  (pure move + typealiases).

### LP-09 · TopDrawer · Policy extraction 1: reconcile/park + de-overlap
**Branch** `claude/lp-09-policy-reconcile` · **Size** M

- From `Tabs/TabController.swift`, extract into a new pure type (new file
  `Screens/TabPlacementPolicy.swift`, platform-neutral — CG-guard idiom):
  the reconcile rules (which display a tab lands on given its `ScreenAnchor`, the
  connected-display set, and `DisconnectPolicy` — park vs move-to-main) and the
  de-overlap fold (settled fractional positions, the persist-back set, guests not
  persisted, `EdgeLayout.minTabGap` semantics). The policy takes value inputs
  (anchors, display IDs, frames) and returns decisions; `TabController` calls it
  and keeps doing the AppKit side effects.
- Add unit tests for the extracted rules (encode current behavior first — write
  the tests against the existing logic before moving it).
- Linux sources+tests gain the new files.
- **Acceptance**: new tests green on both platforms; macOS CI green; no visible
  behavior change (the PR body must argue this from the diff: pure move).

### LP-10 · TopDrawer · Policy extraction 2: drag snap/magnetization + z-order
**Branch** `claude/lp-10-policy-drag` · **Size** M

Same recipe for: `snappedAlongEdge`/quarter-point + neighbor magnetization inputs
and the deterministic z-restack (`topOrder`, `isFrontmost` interplay) — much of
this already lives in `EdgeLayout`; the extraction moves the *controller-side
orchestration decisions* (when to snap, what order to restack) into a pure
`TabDragPolicy`.
**Acceptance**: as LP-09 (new policy tests green both platforms; macOS CI green;
pure-move argument in the PR body).

### LP-11 · TopDrawer · Policy extraction 3: spring-load/peek + hotkey conflicts
**Branch** `claude/lp-11-policy-springload` · **Size** M

Same recipe for: the spring-loaded-drop / drag-peek state machine (states, dwell
timings, which tab opens/peeks when) as `SpringLoadPolicy`, and the hotkey
conflict handling (`failedHotkeySpecs` cache vs bounded owner-swap retry) as
`HotkeyRegistrationPolicy`. Timers stay outside; the policies are pure
state-transition functions.
**Acceptance**: as LP-09.

### LP-12 · TopDrawer · Platform seams 1: volumes, trash, launching
**Branch** `claude/lp-12-seams-volumes` · **Size** M

- Formalize protocols in platform-neutral files: `VolumeListing` (what
  `DisksLister`/`NetworkLister`/`CloudLister`'s FileManager bridges do),
  `TrashServicing` (count/full-empty/open/trash-items/empty — the shape of
  `TrashInspector` + `FileMover.trash/emptyTrash`), `AppLaunching` (the closures
  `ItemLauncher` already injects). macOS conformances wrap the existing code
  unchanged.
- Guard `FileMover`'s `FileManager.trashItem` default argument with
  `#if os(macOS)` (on Linux the default becomes a `TrashServicing`-injected
  closure) — see [03](03-swift-on-linux.md): the symbol does not exist on Linux.
- Linux sources gain: the listers (pure `Volume` cores compile as-is),
  `Launch/ItemLauncher.swift`, `Launch/FileMover.swift`. Tests:
  `DisksListerTests`, `NetworkListerTests`, `CloudListerTests`,
  `ItemLauncherTests`, `FileMoverTests`.
- **Acceptance**: suites green on Linux; macOS green.

### LP-13 · TopDrawer · Platform seams 2: displays, hotkeys, login, icon names
**Branch** `claude/lp-13-seams-display-icon` · **Size** M

- Protocols: `DisplayIdentity` (uuid-for-screen / screen-for-uuid / onChange —
  the `DisplayRegistry` shape, with "screen" as an opaque ID + frame value type on
  Linux), `GlobalHotkeyRegistering` (register/unregister by `HotkeySpec`),
  `LoginItemManaging`. macOS conformances wrap existing code.
- **IconName abstraction**: new `Model/IconName.swift` — a value type wrapping the
  symbol string; `TabGlyph`/`IconStyle` keep their stored SF names (no document
  migration!) but all *rendering* call sites go through
  `IconName(sfSymbol:).resolved(for: .macOS/.linux)`. Add
  `Resources/icon-map.json` (or a Swift table): SF name → chosen Linux icon name,
  seeded for **every symbol in `SymbolPickerView`'s curated list** plus every
  symbol the code references; unmapped names fall back to a generic glyph and log
  once. Choosing the Linux set: per [04](04-ui-frameworks.md) — default to a
  single coherent MIT/Apache set; record the choice in the PR.
- **Acceptance**: macOS CI green (rendering unchanged — resolver returns the SF
  name on macOS); Linux build green; a unit test asserts every curated picker
  symbol has a mapping entry. (The mapping table is mechanical data — it is
  **exempt from the §0.6.2 size cap**, like tests; if the non-data diff still
  balloons, split the map seeding into its own follow-up PR.)

---

## Part 4 — Pict CLI + system-wide overrides

### LP-14 · Pict · `pict` CLI (store operations)
**Branch** `claude/lp-14-pict-cli` · **Size** M

- New executable target `pict-cli` (product name `pict`) in the Pict package,
  source under `Sources/PictCLI/`, depending on PictKit (+ swift-argument-parser).
  Subcommands: `list` (targets + sources from the store), `get <key>`,
  `set <key> <image-file>` (through validator+normalizer, writes entry+PNG),
  `remove <key>`, `path` (prints the store directory).
  Keys use the existing serialized forms (`app:…`, `bundleID:…`, `file:…`) plus
  accept a bare `.desktop` file path (stored as its path under the existing
  `app:` kind).
- Builds and runs on macOS too (harmless; useful for debugging).
- **Acceptance**: unit tests for argument→action mapping; an integration test
  driving the CLI binary against a temp `XDG_DATA_HOME`; both CIs green.

### LP-15 · Pict · `.desktop` override sync
**Branch** `claude/lp-15-desktop-overrides` · **Size** M

- New PictKit (or PictCLI) component `DesktopOverrideSync` (Linux-only,
  `#if os(Linux)`): for each store entry keyed to a desktop entry, regenerate
  `~/.local/share/applications/<id>.desktop` as *the current system entry with
  only `Icon=` replaced* by the store PNG's absolute path; remove overrides for
  deleted entries; never touch entries Pict didn't generate (mark with
  `X-Pict-Managed=true`). `pict sync-overrides [--watch]` (watch = the LP-05
  watcher + a watch on the system applications dirs).
- Details in the Pict repo's `docs/linux-port.md` §Applying icons system-wide —
  follow it exactly (staleness rule, update-survival rationale).
- **Acceptance**: integration tests against temp `XDG_DATA_HOME`/`XDG_DATA_DIRS`
  fixtures (fake system `.desktop` files); both CIs green.

---

## Part 5 — `topdrawerd` (the Linux daemon)

*All Part 5+ Linux-only code lives under `linux/` in the TopDrawer repo (its own
SwiftPM package, e.g. `linux/Package.swift` with the daemon and frontend targets),
depending on the root `MacDring` package via `.package(path: "..")` and on PictKit
via its git URL. Nothing under `linux/` is seen by the Xcode project.*

### LP-16 · TopDrawer · Daemon skeleton + D-Bus + systemd unit
**Branch** `claude/lp-16-daemon-skeleton` · **Size** M-L

- `linux/Sources/topdrawerd/`: loads the `TabStore` document from
  `~/.local/share/MacDring/launcher.json` (the XDG mapping gives this for free),
  runs a main run loop, and exports **D-Bus session-bus name `ch.lkmc.TopDrawer`**
  with an object implementing `ch.lkmc.TopDrawer1`:
  - Methods: `GetDocument() -> s` (the launcher JSON), `Launch(s itemID) -> b`,
    `AddDroppedURIs(s tabID, as uris) -> b`, `Ping() -> s`.
  - Signals: `DocumentChanged()`.
  D-Bus library: **`wendylabsinc/dbus`** (vetted in Part 10 — object export,
  signals, and a codegen plugin from `.dbus.xml` all confirmed; you must call
  `org.freedesktop.DBus.RequestName` yourself to claim the bus name). If it
  proves unable in practice, fall back per Part 10 and say so in the PR.
- Ship `linux/systemd/topdrawerd.service` (user unit, `WantedBy=default.target`)
  and a `linux/README.md` (build, install, `busctl` smoke commands).
- CI: extend the Linux job to `swift build --package-path linux` and run the
  daemon's unit tests (D-Bus integration tests run under `dbus-run-session`).
- **Acceptance**: `dbus-run-session -- swift test --package-path linux` green;
  `busctl --user call … Ping` documented and demonstrated in tests.

### LP-17 · TopDrawer · Daemon: volumes, folder watch, trash
**Branch** `claude/lp-17-daemon-volumes` · **Size** M

- Implement `VolumeListing` (LP-12 protocol) from `/proc/self/mounts`
  (+ `/proc/self/mountinfo`): classify per [05](05-topdrawer-port.md)'s table
  (removable via `/sys/block/*/removable` + `/media/$USER` convention; network =
  fstype set; cloud = `fuse.rclone` etc. + well-known dirs incl.
  `~/.dropbox/info.json`). Eject via `udisksctl unmount -b` + `power-off`
  (fallback `gio mount -e`).
- Folder-tab watching + trash: inotify watchers. The LP-05 wrapper lives in
  PictKit (the other repo) and the root `MacDring` package has no PictKit
  dependency — so **copy** the ~100-line wrapper into
  `MacDring/Common/INotifyWatcher.swift` under a **whole-file `#if os(Linux)`
  guard (mandatory: Xcode's synchronized groups will compile any new file under
  `MacDring/`)**, and note the deliberate duplication in the PR body.
  `TrashServicing` impl per spec paths
  (`$XDG_DATA_HOME/Trash/files` count; `gio trash <file>`; `gio trash --empty`;
  open via `xdg-open trash:///` falling back to the files dir).
- Extend the D-Bus interface: `GetVolumes() -> s` (JSON), `Eject(s volumeID)`,
  `GetTrashState() -> (bu)`, signals `VolumesChanged`, `TrashChanged`.
- **Acceptance**: unit tests with fixture mount tables + temp trash dirs; manual
  smoke via `busctl` documented in the PR body.

### LP-18 · TopDrawer · Daemon: recents + fresh
**Branch** `claude/lp-18-daemon-recents` · **Size** M

- `RecentFilesQuerying` (LP-08) Linux impl #1: parse
  `$XDG_DATA_HOME/recently-used.xbel` (FoundationXML), map to `RecentFileHit`s,
  inotify-watch the file. Impl #2 (fresh): recursive inotify over the configured
  scopes (Downloads/Desktop/Documents by default) + a startup scan ranking by
  birth-time via `statx` (small C shim if Glibc doesn't expose it — keep the shim
  under `linux/Sources/CShims/`) with mtime fallback — `FreshScanner`'s
  injectable `dateAdded` is the hook.
- Wire the Recents/Fresh tab kinds in the daemon document responses; D-Bus:
  `GetRecents(s tabID)`, signal `RecentsChanged(s tabID)`.
- **Acceptance**: xbel fixture tests; fresh-scan temp-dir tests (create files,
  expect ordering); LocalSearch/Tracker integration is explicitly **out of scope**
  (a follow-up — record it).

### LP-19 · TopDrawer · Daemon: launching, running apps, recents recording
**Branch** `claude/lp-19-daemon-launch` · **Size** M

- `AppLaunching` Linux impl: `.desktop` enumeration + parse (own parser: the
  spec's key-value format; honor `NoDisplay`, `Hidden`, `Exec` field codes `%f/%F/
  %u/%U` stripping; dedupe by desktop-file ID across `$XDG_DATA_HOME` +
  `$XDG_DATA_DIRS`); launch default = `gio open <uri>` / `xdg-open`; open-with =
  `gio launch <desktop-file> <files>`; reveal = `org.freedesktop.FileManager1
  .ShowItems` D-Bus with `xdg-open <parent-dir>` fallback.
- Running-apps heuristic (stock-GNOME tier of [02](02-desktop-constraints.md)):
  systemd user scopes (`app-*.scope` via the systemd D-Bus) + `/proc` comm/cmdline
  matching against `Exec`. Expose `GetRunningAppIDs() -> as` + signal.
- Record launches into `RecentsStore` (already portable).
- **Acceptance**: parser unit tests (fixtures incl. snap/flatpak-exported
  entries); launch calls mocked; both CIs green.

---

## Part 6 — Layer-shell frontend (KDE / wlroots / COSMIC / Mir)

*C interop starts here. Copy patterns from
[dexbar](https://github.com/SucculentGoose/dexbar) (GTK4 + layer-shell from Swift)
and keep every `systemLibrary` target tiny. A C shim (`linux/Sources/CGtkShim/`)
provides `g_signal_connect` wrappers (it's a varargs macro Swift can't call).*

### LP-20 · TopDrawer · GTK4 + layer-shell "hello dock"
**Branch** `claude/lp-20-layer-shell-hello` · **Size** M

- `linux/Package.swift` gains `CGtk4` (`pkgConfig: "gtk4"`) and `CGtkLayerShell`
  (`pkgConfig: "gtk4-layer-shell-0"`) systemLibrary targets + the shim target;
  executable `topdrawer-shell`. **gtk4-layer-shell is not packaged on Ubuntu
  24.04** — the CI container must build it from source per the Part 10 recipe
  (add those steps to `linux-ci.yml` in this PR); runtime targets are Ubuntu
  25.10+/26.04 and other distros shipping it.
- Renders one anchored, undecorated strip on a configured edge/monitor via
  gtk4-layer-shell (layer `top`, margin, exclusive zone 0), logs pointer
  enter/leave and clicks, reads tab data from the daemon over D-Bus (client side
  of LP-16).
- CI can only **build** this (no compositor); add it to the Linux build job.
  Manual verification: run under a nested compositor if available; otherwise
  document the expected behavior and verify visually in the first real
  environment available — say so honestly in the PR.
- **Acceptance**: builds in CI; D-Bus client covered by tests against a mock
  service under `dbus-run-session`.

### LP-21 · TopDrawer · Tab pills + placement
**Branch** `claude/lp-21-tabs-render` · **Size** M-L

- Draw tab pills (rounded trapezoid, color, glyph via the LP-13 icon mapping,
  label) with cairo in a `GtkDrawingArea` per tab window; one layer-shell surface
  per tab, placed from `EdgeLayout` outputs through a **single y-flip adapter**
  (`LinuxScreenSpace.swift`, unit-tested — [05](05-topdrawer-port.md) §Surprises
  item 1; measure against the output's *usable* area/exclusive zones).
- Click → emits `ToggleDrawer(tabID)` to the daemon (drawer UI arrives next).
- **Acceptance**: adapter + metrics unit tests green; builds in CI.

### LP-22 · TopDrawer · Drawer window
**Branch** `claude/lp-22-drawer` · **Size** L

- Drawer as a layer-shell surface adjacent to its tab: icon grid (GTK widgets,
  PNG icons via GTK's own loaders — file paths come from the icon pipeline),
  `DrawerMetrics` for sizing, launch on click via daemon, notes tab (TextView +
  the portable `MarkdownText` core), folder/disks/network/cloud/recents/fresh
  content from daemon data, type-to-find over `DrawerSearch` with key handling.
- **Acceptance**: view-model unit tests (grid population from document fixtures);
  builds in CI.

### LP-23 · TopDrawer · Drag & drop
**Branch** `claude/lp-23-dnd` · **Size** M

- `GtkDropTarget` on pills and drawer accepting `GdkFileList`/uri-list, **actions
  COPY|MOVE** ([02](02-desktop-constraints.md) — Nautilus rejects COPY-only),
  `:drop(active)` CSS highlight, spring-open on hover-with-drag, drop-on-slot →
  daemon `AddDroppedURIs`, drop-on-app-item → open-with, drop-on-folder-item →
  move via `FileMover` semantics, drop-on-trash → `gio trash`.
- **Acceptance**: target-resolution logic (cursor→slot mapping reusing
  `ExternalDropTarget.target(at:)`) unit-tested; builds in CI.

### LP-24 · TopDrawer + Pict · Linux icon ladder
**Branches** — this item is **two PRs, strictly sequenced**: first
`claude/lp-24a-artwork-theme` in **Pict** (the `ArtworkProviding` theme-lookup
implementation), babysat and merged per the full §0.6 protocol; then
`claude/lp-24b-icon-ladder` in **TopDrawer** · **Size** M total

- Implement the resolve ladder for Linux mirroring `ItemView.resolveIcon`'s
  order: user custom image → generated `IconStyle` tile (pure raster backend from
  LP-04) → PictKit store → theme icon for the app (`GtkIconTheme` lookup — one C
  call — or spec-following file resolution) → generic fallback. Implement
  PictKit's Linux `ArtworkProviding` (LP-06 placeholder) with the theme lookup.
  Favicons for URL items: port `FaviconCache` logic with the gdk-pixbuf CLI-free
  route — decode via the LP-04 PNG codec + the ~100-line ICO container splitter
  ([05](05-topdrawer-port.md) capability map) feeding PNG members to the codec.
- **Acceptance**: ladder unit tests with fixture stores/themes; ICO splitter
  tests with a real multi-entry favicon fixture.

### LP-25 · TopDrawer · Hotkeys + concealment
**Branch** `claude/lp-25-hotkeys-conceal` · **Size** M

- GlobalShortcuts portal client (D-Bus: `CreateSession`, `BindShortcuts`,
  `Activated` signal), keyed per tab; **capability-probe by calling, never by
  interface presence** ([02](02-desktop-constraints.md)); GSettings media-keys
  fallback documented but not auto-written (explicit user action via settings
  only). Auto-hide/auto-fade: sliver strips (1-2 px layer-shell surfaces) whose
  pointer-enter reveals — reuse `TabConcealment` semantics; drag-peek = reveal on
  drag-enter of the sliver.
- **Acceptance**: portal client tested against a mock D-Bus service; conceal
  state machine tests (reuse the LP-11 policies).

### LP-26 · TopDrawer · Linux settings surface
**Branch** `claude/lp-26-settings` · **Size** M

- Minimal GTK preferences window: General (launch at login via XDG autostart
  file, single-click, animations), Appearance (translucency→opacity, icon size,
  grid), Tabs (list, add/remove/rename, color, glyph picker from the mapping
  table, per-tab hotkey binding via the portal dialog), layout import/export
  (file dialogs, same JSON). Plus `topdrawer-cli` for scripted tweaks.
- **Acceptance**: settings round-trip tests through `Preferences`/`TabStore`;
  builds in CI.

---

## Part 7 — GNOME Shell extension (stock Ubuntu)

*GJS/ESM, GNOME 48–50. Follow [02](02-desktop-constraints.md) §GNOME+extension and
the verification appendix in [07](07-roadmap.md): normal windows + `make_above`
(never DOCK type), `unmake_above()` before `make_above()`, match windows by
wm_class, positions via `move_frame`. Study
[ddterm](https://github.com/ddterm/gnome-shell-extension-ddterm)'s `shell/wm.js`.*

### LP-27 · TopDrawer · Extension skeleton + window management
**Branch** `claude/lp-27-gnome-ext` · **Size** L

- `linux/gnome-extension/topdrawer@lkmc.ch/`: `metadata.json`
  (shell-version 48–50), `extension.js` — D-Bus proxy to the daemon; the frontend
  gains a `--gnome` mode (plain `GtkWindow`s instead of layer-shell, wm_class
  `topdrawer-shell`); the extension finds those windows and applies
  `move_frame`/`make_above`/`stick` per daemon-provided geometry (the daemon
  computes it from `EdgeLayout` + the extension's monitor feed).
- Dev loop: `gnome-extensions pack/install` + a nested shell where the
  environment permits (`dbus-run-session -- gnome-shell --nested --wayland` on
  GNOME ≤ 48; the flag is renamed `--devkit` on GNOME 49+ — Part 10); otherwise
  ship with careful code review and mark runtime verification as pending in the
  PR (honestly).
- **Acceptance**: JS passes `eslint` (add a config); the D-Bus contract is
  exercised by daemon-side tests; installation documented.

### LP-28 · TopDrawer · Extension: reveal, hotkeys, running apps
**Branch** `claude/lp-28-gnome-ext-input` · **Size** M

- `Meta.Barrier` pressure barriers per concealed tab edge → D-Bus reveal calls;
  `Main.wm.addKeybinding` for per-tab hotkeys (settings schema); running-apps
  feed from `Shell.WindowTracker` → daemon signal; monitor-identity feed
  (Mutter's EDID-based info) → daemon.
- **Acceptance**: extension JS passes eslint; the barrier/keybinding/running-apps
  D-Bus contract is exercised by daemon-side tests against a mock extension
  client; manual nested-session verification noted in the PR.

### LP-29 · TopDrawer · Extension packaging + first-run
**Branch** `claude/lp-29-gnome-ext-package` · **Size** S-M

- `gnome-extensions pack` artifact in CI; INSTALL docs (submission to
  extensions.gnome.org is a human step — prepare the zip and instructions);
  frontend first-run detection of GNOME-without-extension → notification pointing
  at install instructions (deb-installed extensions are not auto-enabled —
  [07](07-roadmap.md) appendix).
- **Acceptance**: the pack step produces an installable zip in CI; install docs
  walk a fresh Ubuntu 26.04 user end-to-end; first-run detection covered by a
  unit test on the detection logic.

---

## Part 8 — Packaging and updates

### LP-30 · TopDrawer · Debian packaging
**Branch** `claude/lp-30-deb` · **Size** M

- `linux/packaging/build-deb.sh` (plain `dpkg-deb` layout is fine): installs
  `topdrawerd`, `topdrawer-shell`, `topdrawer-cli`, the systemd user unit, XDG
  autostart entry for the shell, the extension zip under
  `/usr/share/topdrawer/`, icons, `.desktop` entry. CI job builds the deb as an
  artifact on tags and pushes it to the GitHub release (extend the existing
  release workflow guardedly — do not disturb the macOS release path).
- **Acceptance**: `lintian` reasonably clean; deb installs+runs in a container
  smoke test (`systemd` not required for the smoke: binaries + files land).

### LP-31 · TopDrawer · Linux update flow + docs
**Branch** `claude/lp-31-updates-docs` · **Size** S

- `GitHubRelease.preferredAsset` gains `.deb`/`.AppImage`/`.tar.gz` preference on
  Linux (`#if os(Linux)`); reveal-downloaded-file via FileManager1/`xdg-open`.
  Root README gains a Linux section; `docs/linux-port/README.md` gains a status
  table linking merged LP PRs.
- **Acceptance**: asset-preference unit tests green on both platforms (macOS
  behavior unchanged, asserted); README renders correctly.

### LP-32 · Pict · Debian packaging for `pict`
**Branch** `claude/lp-32-pict-deb` · **Size** S

Same recipe as LP-30 for the `pict` CLI (+ future editor); README update.
**Acceptance**: deb builds in CI, installs in a container smoke test, and
`pict list` runs from the installed path; README renders.

---

## Part 9 — Pict editor app

### LP-33 · Pict · GTK editor shell
**Branch** `claude/lp-33-editor-shell` · **Size** L

- New target under `App/LinuxEditor/` (or `linux/` — keep it out of the Xcode
  app's directory): GTK4 window with the app list (LP-19's `.desktop` enumeration
  — lift that parser into a small shared package or duplicate minimally and note
  it), search field, per-row current icon + source caption
  (`IconArtworkStatus`), set-from-file (file dialog → `IconImport.route` →
  validator → store) and remove/revert. Reuses `IconEditorModel`'s orchestration
  where it compiles (extract its `NSOpenPanel`/`NSImage` corners first — small
  Pict-side change, keep it in this PR).
- **Acceptance**: model logic tests on Linux; builds in CI.

### LP-34 · Pict · SVG ingestion + local icon sets
**Branch** `claude/lp-34-editor-svg` · **Size** M

- SVG rasterization on Linux: shell out to `rsvg-convert` (`librsvg2-bin`) —
  run it with a sanitized environment, an empty working directory, and the flags
  vetted in the revision notes (Part 10) to prevent external-resource loading;
  keep `isSVG` sniffing + `scalable()` viewBox synthesis from the existing code
  in front of it; **bump `IconRenderCache.renderVersion`**. Icon sets v1 = local
  system themes (`/usr/share/icons`, `~/.local/share/icons`): reuse
  `IconSetProvider`/`IconNameGuess`/`IconSetAutoMatch` (already portable) over a
  local-theme catalogue.
- **Acceptance**: rasterizer tests with fixture SVGs incl. a no-viewBox Papirus
  icon and a hostile external-ref SVG (must produce no network access — assert
  via an env with no resolver / by inspecting the tool's behavior per the vetted
  flags); both CIs green.

### LP-35 · Pict · Remote icon sets + Iconify search
**Branch** `claude/lp-35-editor-remote` · **Size** M

- `IconSetInstaller` on Linux: add `--wildcards` to the tar invocation on Linux
  (**GNU tar**; keep bsdtar behavior on macOS), port its tests (they build
  fixture tarballs — adjust for GNU tar's flags), switch test stubbing to
  `configuration.protocolClasses` injection ([03](03-swift-on-linux.md)).
  `RemoteIconFetcher`: replace `URLSession.bytes(for:)` (does not exist on
  Linux) with a delegate-based data task preserving the **count-as-you-go cap**;
  share the implementation with macOS if clean, else `#if` it.
  Iconify search + `CollectionCache` (plain `data(from:)`) wired into the editor.
- **Acceptance**: installer + fetcher + client tests green on both platforms.

### LP-36 · Pict · Web picker on WebKitGTK 6.0
**Branch** `claude/lp-36-web-picker` · **Size** L

- `CWebKitGTK` systemLibrary (`pkgConfig: "webkitgtk-6.0"`); embed a web view in
  the editor; port `WebImageBrowser`'s flow: inject the existing JS (it ports
  verbatim) via `WebKitUserContentManager` script + message handler
  (`window.webkit.messageHandlers` — same page-side API); intercept the
  `context-menu` signal and read `webkit_hit_test_result_get_image_uri()`
  (synchronous — the macOS race workaround is unnecessary, delete it on this
  path); "Use This Image" → `OriginalImageResolver` → `RemoteIconFetcher` →
  candidate preview (`IconCandidate` logic is portable) → store. Ephemeral
  network session. Copy the embedding recipe from
  [silveran-reader](https://github.com/kyonifer/silveran-reader)'s
  `WebKitBridge.swift`.
- **Acceptance**: bridge-payload and candidate logic tests on Linux; builds in
  CI; manual end-to-end noted in the PR.

---

## Part 10 — Revision notes (mechanics verified 2026-08-23)

*This section pins the concrete choices the items above defer to. Every pin below
was verified against primary sources (package archives, project repos, SwiftPM
source, or empirically on an Ubuntu 24.04 box) on 2026-08-23. If reality disagrees
with a pin, follow §0.5's deviation rule.*

**SwiftPM mechanics** (all confirmed in swift-package-manager source):
- A target with `sources:` compiles only the listed files; unlisted files in the
  target `path` are silently ignored (no warning). A listed path that doesn't
  exist produces a warning — treat any "Invalid Source" warning as an error.
  `exclude:` takes precedence over `sources:`.
- `#if os(Linux)` in `Package.swift` is evaluated on the **build host** (the
  manifest is compiled and run as a host executable) — correct for our native
  builds; do not combine with cross-compilation.
- `.product(name:package:condition: .when(platforms: [.linux]))` needs
  swift-tools ≥ 5.3 and applies to the platform being built **for**.
- Root `Package.swift` + `.xcodeproj` coexist safely **as long as `-project` is
  always passed to xcodebuild** (both repos' CI does). Never run bare `xcodebuild`
  in these repos.

**Crypto**: depend on `apple/swift-crypto` (`"1.0.0"..<"5.0.0"`, product
`Crypto`) with the Linux-only product condition, and use the
`#if canImport(CryptoKit) import CryptoKit #else import Crypto #endif` idiom in
shared files — needed here precisely because the Xcode build must not acquire the
package dependency. `SHA256` API is identical (shared test suite upstream).

**PNG codec (LP-04)**: `tayloraswift/swift-png` — pinned `from: "4.5.0"`
(current 4.5.1, 2026-03; CI on Swift 6.3.3 Linux; pure Swift, no zlib/C deps).
API: decode `let image: PNG.Image = try .decompress(path:)` →
`image.unpack(as: PNG.RGBA<UInt8>.self)` + `image.size`; encode
`PNG.Image(packing:size:layout: .init(format: .rgba8(palette: [], fill: nil)))`
→ `try image.compress(path:level: 9)`. PNG is straight-alpha: convert to/from
`PixelImage`'s premultiplied samples at this boundary (round-trip test required).

**D-Bus (LP-16+)**: `wendylabsinc/dbus` 0.4.1 (pure Swift on SwiftNIO,
Linux-only, active, tools 6.0). Server: `DBusObjectServer` +
`ExportedObject(path:interfaces:)` + `Interface(name:methods:properties:signals:)`
+ `Method(...handler:)`; introspection XML auto-generated; a
`DBusCodegenPlugin` generates client proxies and server scaffolding from
`.dbus.xml` files — use it. Signals: `DBusRequest.createSignal(...)` +
`connection.send(...)`. Client: `DBusClient.withSessionBus(auth:)`. **There is no
RequestName helper** — claim `ch.lkmc.TopDrawer` by calling
`org.freedesktop.DBus.RequestName` yourself (one method call). Fallbacks
(PureSwift/DBus: currently unconsumable manifest; suransea/dbus-swift: stale)
were evaluated and rejected — don't switch without a new reason.

**inotify (LP-05/17/18)**: `import Glibc` exposes the functions but NOT reliably
the `IN_*` macros, and `struct inotify_event`'s flexible array member is awkward.
Use the proven pattern from `aus-der-Technik/FileMonitor`: a tiny C system module
(`module CInotify [system] { header "shim.h" }` with `#include <sys/inotify.h>`)
plus the `IN_*` constants **hard-coded in a Swift enum** (`IN_CREATE =
0x00000100`, `IN_DELETE = 0x00000200`, `IN_MOVED_TO = 0x00000080`,
`IN_CLOSE_WRITE = 0x00000008`, `IN_MOVED_FROM = 0x00000040`); parse the event
buffer manually (header is 16 bytes + `len` name bytes).

**Birth time (LP-18)**: glibc 2.39 (noble) has `statx()`; the robust route is a
one-function C shim (`int64_t file_btime(const char *path)`) that calls `statx`
with `STATX_BTIME`, checks `stx_mask & STATX_BTIME`, and returns −1 when the
filesystem doesn't provide btime (then fall back per `FreshScanner`'s ladder).

**gtk4-layer-shell (LP-20)** — the one genuinely awkward pin:
- **NOT packaged on Ubuntu 24.04 noble** (only the GTK3 `libgtk-layer-shell*`
  packages exist there — do not confuse them). Packaged from Ubuntu 25.10
  (`libgtk4-layer-shell0` / `libgtk4-layer-shell-dev` 1.0.4) and 26.04 (1.3.0).
- In the noble-based CI container, build it from source (pin the upstream tag):
  deps `libwayland-dev wayland-protocols libgtk-4-dev gobject-introspection
  libgirepository1.0-dev meson ninja-build`; then `meson setup build &&
  ninja -C build && ninja -C build install && ldconfig`.
- Runtime support statement for the frontend: Ubuntu 25.10+/26.04 (distro
  package) and any distro shipping gtk4-layer-shell; noble users build from
  source or use the deb's vendored copy (decide at LP-30; vendoring is
  acceptable — it's MIT).

**gio CLI (LP-17/19)**: the binary package is **`libglib2.0-bin`** (glib 2.80 on
noble). All required subcommands confirmed present: `gio trash FILE`,
`gio trash --list`, `gio trash --empty`, `gio mount -l`, `gio mount -e`,
`gio launch app.desktop [FILES]`, `gio open URI`.

**WebKitGTK (LP-36)**: noble ships `libwebkitgtk-6.0-dev` (pkg-config
`webkitgtk-6.0`) at 2.50.x via updates; the GTK3-era `libwebkit2gtk-4.1-dev` also
exists — use 6.0 only.

**rsvg-convert (LP-34)**: package `librsvg2-bin` (2.58 on noble; Rust CLI).
Flags: `-w/-h` (size), `-o` (output), `-f png` default, `-` = stdin. **There is
no `--base-uri` flag** — the base is derived from the input file's path, so the
sandbox recipe is: write the SVG into a **fresh empty temp directory** and invoke
`rsvg-convert` on that file; empirically verified security profile: remote
http(s) refs are never fetched (libxml2 `XML_PARSE_NONET`), local file refs
resolve only within the input file's directory subtree (`..` and absolute paths
outside it are blocked), XXE is blocked. The empty-dir recipe therefore denies a
hostile SVG everything. Keep a regression test with a hostile SVG fixture.

**GNOME Shell dev loop (LP-27)**: `gnome-extensions
pack/install/enable` CLI confirmed. Nested-session flag differs by version:
GNOME ≤ 48 `dbus-run-session -- gnome-shell --nested --wayland`; **GNOME 49+
renamed it to `--devkit`** (Ubuntu 26.04 = GNOME 50 → `--devkit`).

**CI containers (LP-01/02)**: `container: swift:6.3` == `swift:6.3-noble`
(same image; Ubuntu 24.04). Never use `-slim` tags (no compiler). Modern
`actions/checkout` handles `safe.directory` itself, but any additional git use
(SwiftPM git deps included) may need
`git config --global --add safe.directory "$GITHUB_WORKSPACE"`. Include the image
tag in any build-cache key.

---

## Done means done

The port is complete when: both repos' Linux CI is green on main; `topdrawerd` +
`topdrawer-shell` deliver tabs/drawers with launch, DnD, hotkeys, conceal/reveal,
volumes/trash/recents/fresh on a layer-shell compositor; the GNOME extension
delivers the same on stock Ubuntu; `pict` CLI + editor manage the store and
`.desktop` overrides; debs build in CI. Follow-ups collected along the way
(LocalSearch integration, AppImage, Flathub-shaped editor split, SwiftCrossUI
adoption) live as issues, not as scope.
