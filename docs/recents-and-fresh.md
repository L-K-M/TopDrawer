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
| **Top Drawer** (default) | Only what you've opened *from Top Drawer* — its own launch log, kept in `UserDefaults`. This is the original behavior; existing tabs keep it. |
| **System** | Documents you've recently opened **anywhere** — double-clicked in Finder, opened in any app — read live from Spotlight (`kMDItemLastUsedDate`). |
| **Both** | The two, merged most-recent-first and de-duplicated by location. |

| | |
|---|---|
| **Item kind** | the target's own kind (app / file / folder / link) |
| **Click** | re-open the target |
| **Header** | **Clear** empties Top Drawer's own history (the System part is the live Spotlight index and isn't Top Drawer's to clear) |

The **Top Drawer** part shows instantly; the **System** part is gathered asynchronously
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

### Spotlight-only by default — direct check opt-in

By default the Fresh tab is filled **entirely from the Spotlight index**: index reads
need no permission at all, so a default Fresh tab can never trigger macOS's
folder-access consent dialogs — it shows nothing rather than ask for anything. The
trade-off: on a Mac where Spotlight is off, still indexing, or told to skip the
landing zones, that means it really shows nothing.

Because Spotlight isn't reliable on every Mac, **Settings → General → Fresh tabs →
"Also check Downloads, Desktop & Documents directly"** adds Top Drawer's own
filesystem check of the landing zones **in addition to** Spotlight: `FreshScanner`
reads the **top level** of each folder and ranks by the same Date-Added attribute,
`FreshLister.merge` folds the two listings together (newest first, de-duplicated by
location), and the direct read also seeds the drawer the instant it opens. So you get

- **Spotlight off / unreliable** — the direct check alone fills the tab (anything
  that lands at the top level of those folders; only files buried in their
  sub-folders are missed),
- **Spotlight on** — both, the index still contributing the deeper sub-folder hits,
- **partly indexed** — their union.

The direct read is what trips macOS's **one-time folder-access consent prompts**
(one per folder), which is why it is **off by default** and why flipping the toggle
on fires the prompts right there — an explicit opt-in that owns its consent moment,
never a surprise at launch (FB1 / PR #61). The pill's "just landed" dot follows the
same rule: Spotlight-only by default, with the direct scan joining in when opted
in — either source lights it.

## How it works

The **system** part of both tabs is backed by Spotlight through a single small wrapper,
`MacDring/Store/SpotlightQuery.swift` — an `NSMetadataQuery` that ranks by
`kMDItemLastUsedDate` (Recents · System) or `kMDItemDateAdded` (Fresh). Unlike the
other listers it is **asynchronous** (Spotlight gathers over time), so it delivers
its results through a completion once gathering finishes, and the controller resizes
the open drawer to fit. The Fresh tab additionally has `FreshScanner`, a synchronous
direct-filesystem scan that backs it **without** Spotlight when the opt-in direct
check is on (see above). The pure mapping into ordered, slotted `DrawerItem`s — and
the merge of the scan with the Spotlight results — lives in `FreshLister` /
`RecentsLister` and is unit-tested.

Like the Network and Cloud tabs, the items are **transient**: nothing is written to
`launcher.json`, and each item carries a plain `url` (no bookmark), so a closed tab
costs nothing and an open one reflects the current index.

## No special permission

Spotlight is queried for the **index** only — file locations and dates — never file
*contents*, and opening an item is the same user-initiated `NSWorkspace` open every
other tab uses. So these tabs keep Top Drawer's no-scary-permissions promise: no Full
Disk Access, no Accessibility, no global monitors, and — by default — no
folder-access consent dialogs. The trade-off is that both see only what Spotlight
indexes for you; anything it has been told to skip simply doesn't appear, and with
Spotlight off the **Recents · System** source degrades to empty — quietly, without
ever hitting a permission wall. A **Fresh** tab degrades the same way by default;
the one exception is the opt-in direct check above, where the user has explicitly
chosen to answer macOS's per-folder access prompts to keep Fresh working without
Spotlight.

## Customizing an item's icon

As with the other live tabs, you can give any item your own icon —
**right-click → Customize Icon…** — and the override is remembered per path across
re-lists. See [custom item icons](custom-icons.md).
