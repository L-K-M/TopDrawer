# Top Drawer

Screen-edge tabs that open drawers of your apps, files, folders, and links. Inspired by the classic **[DragThing](https://www.dragthing.com/)**. *(Formerly known as MacDring.)*

**Latest release:** v<!-- version -->1.8.0<!-- /version --> · [Download](https://github.com/L-K-M/MacDring/releases/latest)

![Screenshot](screenshot.png)

Tabs sit against the edges of your screens. Click one and a
drawer slides out with whatever you put there. Drag files onto a tab to add them.
Works across multiple monitors, and your tabs return to exactly where you left
them after a restart.

> [!IMPORTANT]
> LLM Disclosure: Top Drawer was built with substantial help from large language models — primarily Anthropic's Claude, via Claude Code. Much of the code arrived through AI-authored commits and `claude/*` pull-request branches, with agent guidance kept in [`AGENTS.md`](AGENTS.md)

## Features

- **Edge tabs → drawers.** Colored tabs anchored to any screen edge; click (or
  hover) to open a drawer.
- **Eight tab types** — an **items** tab (apps, files, folders, links arranged freely
  in a grid with gaps), a **notes** tab (a quick text scratchpad), a **folder** tab
  (a live, read-only view of a directory's contents), a **disks** tab (your mounted
  ejectable volumes), a **network** tab (your mounted network shares), a **cloud** tab
  (your cloud drives — iCloud, Dropbox, …), a **recents** tab (what you've recently
  opened — from Top Drawer, the whole Mac via Spotlight, or both), and a **fresh** tab
  (files that just arrived — downloads, copies, saves). See the docs for the
  [network & cloud](docs/network-and-cloud-drives.md) and
  [recents & fresh](docs/recents-and-fresh.md) tabs.
- **Holds anything launchable** — applications, files, folders, and URLs. One
  click opens them.
- **Drag-and-drop to add.** Drop files or apps from Finder — or a link dragged from
  a browser's address bar — onto a tab or its open drawer.
- **Spring-loaded drops.** Drag a file onto a tab and its drawer springs open; the
  slot under your cursor **highlights**, and dropping there files the item into that
  slot — onto an app to open it with, onto a folder to move it in.
- **Type to find.** With a drawer open, just start typing to filter it; **↑/↓** move
  the selection, **Return** opens it, **Esc** clears (then closes). Shown on drawers
  with a handful of items or more.
- **Trash item.** Add a Trash to any tab (Settings → Tabs → *Add Trash*): click it to
  open the Trash, or drop files onto it to throw them away.
- **Running-app dot.** Application items show a small green dot when the app is
  running, updating live as apps launch and quit.
- **Per-tab color, name, and glyph** (SF Symbol or letters).
- **Custom item icons.** Right-click any item → *Customize Icon…* to give it a
  colored **folder** or **rounded tile** with an SF Symbol burned in (or pick an
  image file). Works on every tab — see [the docs](docs/custom-icons.md).
- **Multi-monitor support.** Tabs live on a specific display + edge and
  react live to displays connecting, disconnecting, and changing resolution.
- **Stable restore.** Tabs return to the same display and spot after a restart,
  resolution change, or reconnection.
- **Optional per-tab hotkey** to toggle drawers.
- **Layout import / export.** Back up or move your whole arrangement: **Settings →
  Tabs** has export/import buttons that save the tabs-and-items document as a
  JSON file and load it back (importing replaces the current layout, after a
  confirmation).
- **Auto-hide / auto-fade tabs.** Set a tab to get out of the way when idle
  (**Settings → Tabs → When idle**): **Auto-hide** slides it off its edge leaving a
  thin sliver, **Auto-fade** dims it in place (opacity adjustable in **Settings →
  Appearance**). Reveals the moment you move the pointer to that screen edge. Turn on
  **Settings → General → Idle tabs → Reveal all hidden tabs together** to have one
  reveal bring back every hidden tab at once (and hide them together when you leave).

## Build & Run

Requires **Xcode 16+** and **macOS 13+**.

```bash
# Build
xcodebuild -project MacDring.xcodeproj -scheme MacDring -configuration Debug build

# Release build
xcodebuild -project MacDring.xcodeproj -scheme MacDring -configuration Release build

# Run unit tests
xcodebuild -project MacDring.xcodeproj -scheme MacDring -destination 'platform=macOS' test
```

For a convenient local build, `scripts/build.sh` does an incremental Release build
and reveals the app in Finder on success; `scripts/build.sh --clean` resets any
wedged Xcode build daemons and rebuilds from scratch.

For day-to-day development, open `MacDring.xcodeproj` in Xcode and run.

## Usage

1. Launch Top Drawer — it appears as a sidebar icon in the menu bar, and a starter
   **Apps** tab appears on the right edge of your main display.
2. **Click the tab** to open its drawer; click an item to launch it.
3. **Drag files or apps** from Finder onto a tab to add them.
4. **Right-click a tab** → *Configure Tab…* to rename it, change its color/glyph,
   move it to another edge or display, set behavior, or assign a hotkey. **Right-click
   an item** in its drawer → *Customize Icon…* to give it a colored folder/tile +
   SF Symbol icon.
5. Use the menu bar → **New Items / Notes / Folder / Disks / Network / Cloud /
   Recents / Fresh Tab…** to add more (a small dialog sets the name, color, type, and
   folder), or **Top Drawer Settings…** to manage everything. A **Disks** tab lists your
   mounted ejectable volumes; a **Network** tab lists your mounted network shares (click
   to open, eject from the menu); a **Cloud** tab lists your cloud drives such as iCloud
   Drive and Dropbox (click to open); a **Recents** tab lists what you've recently
   opened — from Top Drawer, from the whole Mac via Spotlight, or both (Settings → Tabs →
   *Source*); a **Fresh** tab lists files that just arrived (downloads, copies, saves).
   See [network & cloud](docs/network-and-cloud-drives.md) and
   [recents & fresh](docs/recents-and-fresh.md).

### Customizing

- **Per tab** (right-click → *Configure Tab…*, or **Settings → Tabs**): name,
  color, glyph, edge, display, position, keep-open, **drawer layout (grid / list)**,
  how it idles, and an optional hotkey. **Layout** is a straight per-tab choice; the
  **list** layout is a compact, scrolling Finder-style table — small icons with
  **Date**, **Size**, and **Kind** columns (the date is Date Added for Fresh, last-used
  for Recents, modified for folders). The drawer's **Columns / Rows** size it just like
  the grid (it scrolls past what fits); a narrower drawer shows fewer of the metadata
  columns. Handy for a Fresh tab ordered by when files arrived.
  **Open-on-hover** and **close-when-you-click-elsewhere** follow the global default
  unless you override them here — pick *On* / *Off* for the tab, or *Use global default*
  to follow the global setting again (the clear way to revert).
- **Global** (**Settings → Appearance / General**): **tab style (modern/classic)**,
  drawer translucency (translucent / frosted / solid), icon size, corner radius, tab thickness,
  labels, single vs. double-click to open, the **open-on-hover / close-on-click
  defaults** (overridable per tab), animation speed, the multi-display disconnect
  policy, and launch at login.

## Permissions & Distribution

Top Drawer needs **no special permissions** for its core features — launching uses
`NSWorkspace`, and optional hotkeys use Carbon (no Accessibility grant). It ships
as a menu-bar agent (`LSUIElement`).

The one exception is **Empty Trash**: it asks Finder to empty the Trash via Apple
Events, so the first time you use it macOS prompts once to allow Top Drawer to control
Finder (the app carries the `com.apple.security.automation.apple-events`
entitlement). Declining just leaves the Trash as-is — nothing else needs it.
