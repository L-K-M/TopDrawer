# The Recents and Fresh tabs

Two tab types for getting back to the files you were *just* working with:

- a **Recents** tab lists what you've **recently opened**, and
- a **Fresh** tab lists what **recently arrived** on this Mac.

Both are live, read-only listings — siblings of the [Disks / Network / Cloud
tabs](network-and-cloud-drives.md). Click an item to open it; `⌘`-click reveals it in
Finder; drag it **out** to another app. They take no drops. Create either from the
menu bar → **New Recents Tab…** / **New Fresh Tab…**, or **Settings → Tabs → +**.

## Recents tab

A Recents tab lists the apps, files, folders, and links you've opened, most recent
first. It has a per-tab **Source** (Settings → Tabs → *Source*):

| Source | What it lists |
|---|---|
| **MacDring** (default) | Only what you've opened *from MacDring* — its own launch log, kept in `UserDefaults`. This is the original behavior; existing tabs keep it. |
| **System** | Documents you've recently opened **anywhere** — double-clicked in Finder, opened in any app — read live from Spotlight (`kMDItemLastUsedDate`). |
| **Both** | The two, merged most-recent-first and de-duplicated by location. |

| | |
|---|---|
| **Item kind** | the target's own kind (app / file / folder / link) |
| **Click** | re-open the target |
| **Header** | **Clear** empties MacDring's own history (the System part is the live Spotlight index and isn't MacDring's to clear) |

The **MacDring** part shows instantly; the **System** part is gathered asynchronously
from Spotlight when the drawer opens and fills in a moment later.

## Fresh tab

A Fresh tab lists files that **recently landed** on the Mac — downloaded, copied, or
saved — newest first. It answers *"where did that thing I just grabbed go?"*, in the
spirit of the classic **Fresh**-style utilities.

| | |
|---|---|
| **Ranked by** | **Date Added** — Finder's "Date Added", set when a file arrives in its folder (the filesystem's `addedToDirectoryDate`, which Spotlight mirrors as `kMDItemDateAdded`) |
| **Scans** | your **Downloads**, **Desktop**, and **Documents** — the usual landing zones |
| **Window** | roughly the last month, so the list stays "fresh" rather than unbounded |
| **Item kind** | the file's own kind (file / folder / app) |
| **Click** | open it |

> [!TIP]
> Set the tab's **Layout** to **List** (Settings → Tabs → *Drawer*, or right-click →
> *Configure Tab…*) for a compact, Finder-style table — small icons with **Date Added**,
> **Size**, and **Kind** columns — a natural fit for a Fresh tab read newest-first by
> when files arrived. The list keeps the drawer at its configured size and **scrolls**.
> The same columns appear on **Recents** (last-used date) and **folder** (modified date)
> lists. Layout is a per-tab choice (Grid or List).

### Spotlight-only, on purpose

The Fresh tab is filled **entirely from the Spotlight index**. An earlier build also
did a direct filesystem scan of the landing zones so the tab worked with Spotlight
off — but listing `~/Downloads`, `~/Desktop`, or `~/Documents` directly trips macOS's
folder-access consent dialogs, breaking the app's no-permission promise, so that path
was retired (the scan survives as tested pure logic in `FreshScanner`, unused by the
live app). The trade-off: with Spotlight disabled or the landing zones excluded from
indexing, a Fresh tab shows nothing — and never asks for anything.

## How it works

The **system** part of both tabs is backed by Spotlight through a single small wrapper,
`MacDring/Store/SpotlightQuery.swift` — an `NSMetadataQuery` that ranks by
`kMDItemLastUsedDate` (Recents · System) or `kMDItemDateAdded` (Fresh). Unlike the
other listers it is **asynchronous** (Spotlight gathers over time), so it delivers
its results through a completion once gathering finishes, and the controller resizes
the open drawer to fit. The pure mapping into ordered, slotted `DrawerItem`s lives in
`FreshLister` / `RecentsLister` and is unit-tested.

Like the Network and Cloud tabs, the items are **transient**: nothing is written to
`launcher.json`, and each item carries a plain `url` (no bookmark), so a closed tab
costs nothing and an open one reflects the current index.

## No special permission

Spotlight is queried for the **index** only — file locations and dates — never file
*contents*, and opening an item is the same user-initiated `NSWorkspace` open every
other tab uses. So these tabs keep MacDring's no-scary-permissions promise: no Full
Disk Access, no Accessibility, no global monitors, and no folder-access consent
dialogs. The trade-off is that both see only what Spotlight indexes for you; anything
it has been told to skip simply doesn't appear, and with Spotlight off the
**Recents · System** source and the **Fresh** tab degrade to empty — quietly, without
ever hitting a permission wall.

## Customizing an item's icon

As with the other live tabs, you can give any item your own icon —
**right-click → Customize Icon…** — and the override is remembered per path across
re-lists. See [custom item icons](custom-icons.md).
