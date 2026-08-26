# topdrawerd — the Top Drawer Linux daemon

`topdrawerd` is the background service behind Top Drawer's Linux frontend. It owns
the session-bus name **`ch.lkmc.TopDrawer`** and exports one object,
`/ch/lkmc/TopDrawer`, implementing the **`ch.lkmc.TopDrawer1`** interface. The
layer-shell frontend (LP-20+) talks to it over D-Bus; the macOS app is unaffected —
this package is built only on Linux.

LP-16 built the skeleton; **LP-17** added volumes + Trash; **LP-18** added the Recents
and Fresh tab contents (`GetRecents` + `RecentsChanged`); **LP-19** implements launching
(`Launch` / `OpenWith` / `Reveal`) and records launches into the recents history. Running
apps (`GetRunningAppIDs`) and drop-to-tab (`AddDroppedURIs`) remain follow-ups.

## The interface (`ch.lkmc.TopDrawer1`)

| Member | Signature | Behavior |
| --- | --- | --- |
| `Ping` | `() → s` | Returns `topdrawerd <version> alive` — the liveness smoke test. |
| `GetDocument` | `() → s` | The launcher JSON (`$XDG_DATA_HOME/MacDring/launcher.json`), served verbatim; `{}` if absent. |
| `GetVolumes` | `() → s` | The classified mounted volumes as JSON: `{"volumes":[{"id","name","path","kind","device","ejectable"}]}`, `kind` ∈ `disk`/`network`/`cloud` (LP-17). |
| `Eject` | `(s volumeID) → b` | Unmounts/powers off the volume with that `id` (its mount point); `false` if unknown or it failed (LP-17). |
| `GetTrashState` | `() → b u` | Whether the Trash is empty, and its item count (LP-17). |
| `GetRecents` | `(s tabID) → s` | A Recents/Fresh tab's live contents as JSON: `{"recents":[{"path","name","date"}]}`, `date` = Unix epoch seconds; `{"recents":[]}` (an empty array — always valid JSON, never `{}` or a bare empty string) for any other tab. A `.recents` tab folds in Top Drawer's own launch history for a `macDring`/`both` source (LP-18/LP-19). |
| `Launch` | `(s itemID) → b` | Opens the item with that id (resolved from the launcher document) via `gio open`/`gio launch`, and records a successful open into the recents history; `false` if the id is unknown or the launch failed (LP-19). |
| `OpenWith` | `(s appID, as uris) → b` | Opens `uris` with the application named by its desktop-file id (`gio launch <.desktop>`, `gtk-launch` fallback) (LP-19). |
| `Reveal` | `(s uri) → b` | Reveals a file in the file manager (`org.freedesktop.FileManager1.ShowItems`, opening the parent directory as a fallback) (LP-19). |
| `AddDroppedURIs` | `(s tabID, as uris) → b` | Stub — returns `false`; appending dropped files mutates the launcher document, which lands with the frontend's drag & drop (LP-23). |
| `DocumentChanged` | signal `()` | Emitted when the launcher file changes on disk (a modification-time watch). |
| `VolumesChanged` | signal `()` | Emitted when the set of mounted volumes changes (a `/proc` poll — inotify can't watch `/proc`) (LP-17). |
| `TrashChanged` | signal `()` | Emitted when the Trash contents change (an inotify watch on `Trash/files`) (LP-17). |
| `RecentsChanged` | signal `(s tabID)` | Emitted (per affected tab) when a Recents tab's source (`recently-used.xbel`) or a Fresh tab's landing zone changes (LP-18). |

### Recents & Fresh (LP-18)

- **Recents** (`.recents` tabs) draw from two sources per the tab's `recentsSource`. The
  **system** part is the freedesktop `recently-used.xbel`
  (`$XDG_DATA_HOME/recently-used.xbel`), ranked by each bookmark's last-visited time within
  a 90-day window. The **macDring** part is Top Drawer's own launch history (`RecentsStore`),
  which `Launch` records into (LP-19). A `both` tab folds them, newest-first and de-duplicated
  by URL. The default source is `macDring`, so such a tab is empty until something is launched.
- **Fresh** (`.fresh` tabs) reuse MacDring's `FreshScanner` ranking over the standard
  landing zones (Downloads/Desktop/Documents), with a Linux **birth-time** `dateAdded`
  via `statx(STATX_BTIME)` (a one-function C shim under `linux/Sources/CShims/`),
  falling back to mtime where the filesystem doesn't record a birth time. **Caveat:** a
  birth time is a *creation* time, not macOS's Date-Added (added-to-folder) time — a
  file renamed into a landing zone from the same filesystem keeps its original birth
  time and may never surface as Fresh. Capturing a "first-seen" time from the inotify
  watch and ranking by `max(btime, firstSeen)` is a recorded follow-up.
- Change detection: `recently-used.xbel` is a single file in the busy `$XDG_DATA_HOME`,
  so it's **polled** (mtime); the Fresh landing zones are real directories, so each is
  **inotify-watched**. Either fires `RecentsChanged(tabID)` for every affected tab.
- **Out of scope** (recorded follow-ups): a LocalSearch/Tracker index source for
  Recents/Fresh.

### Launching (LP-19)

`Launch(itemID)` resolves the item from the launcher document (a raw-JSON lookup across
every tab's `items`, descending into `group` children, like `LauncherTabs`) and opens its
`url`. Following the weak-model doctrine, it shells out to the desktop-neutral CLIs rather
than binding GIO through C:

- **Open**: `gio open <uri>` with an `xdg-open` fallback; an `application` item whose target
  is a `.desktop` file launches through `gio launch <.desktop>`.
- **Open-with** (`OpenWith`): resolve the desktop-file id to its `.desktop` path and
  `gio launch <.desktop> <files>`, falling back to `gtk-launch <id> <files>`.
- **Reveal** (`Reveal`): the freedesktop `org.freedesktop.FileManager1.ShowItems` D-Bus
  method (via `gdbus`), which selects the file in its folder; falls back to opening the
  parent directory.

A `.desktop` **enumerator** (`DesktopEntryScanner`) reads the installed applications across
`$XDG_DATA_HOME` + `$XDG_DATA_DIRS` (`applications/`), deduplicated by desktop-file id with
user entries shadowing system ones, honoring `NoDisplay`/`Hidden` and the `Exec` field
codes (`%f/%F/%u/%U` expansion, others dropped). A successful `Launch` records the target
into `RecentsStore` (the macDring recents source above).

- **Out of scope** (recorded follow-ups): running-apps detection (`GetRunningAppIDs` + a
  change signal, via systemd user `app-*.scope` and `/proc`) — split out as the next item;
  `AddDroppedURIs` (appending dropped files to a tab) awaits the launcher-document write
  path (LP-23).

### Volume classification (LP-17)

Volumes come from `/proc/self/mountinfo`, filtered to user-facing mounts (pseudo and
system filesystems dropped), and classified to mirror the macOS Disks/Network/Cloud
docks:

- **disk** — a real block device that is removable (`/sys/block/<base>/removable`) or
  auto-mounted under `/media/$USER` or `/run/media/$USER`. Ejected via `udisksctl
  unmount -b` + `power-off -b`, falling back to `gio mount -e`.
- **network** — a remote-share fstype (`cifs`, `nfs`, `fuse.sshfs`, `davfs`, …).
  "Ejected" (disconnected) via `gio mount -u`.
- **cloud** — an `rclone` FUSE mount, plus Dropbox via its documented
  `~/.dropbox/info.json`. gvfs/GOA providers (`google-drive://`, `onedrive://`) live
  inside the single `fuse.gvfsd-fuse` root rather than as separate mounts, so surfacing
  them needs `gio mount -l` — a documented follow-up.

Trash follows the freedesktop spec: state is the count under
`$XDG_DATA_HOME/Trash/files` — the **home trash only**. Per the spec, `gio trash`
places an item from a *different* filesystem (a USB stick, a network mount) into
that volume's own `.Trash-$UID`, which `GetTrashState`/`TrashChanged` do not yet
count or watch — a documented follow-up (it can reuse this LP's volume
enumeration). Trashing/emptying (when wired to drops) uses `gio trash` (from
`libglib2.0-bin`).

## Build

```sh
swift build --package-path linux -c release
```

The daemon uses [`wendylabsinc/dbus`](https://github.com/wendylabsinc/dbus) (a pure
Swift D-Bus implementation on SwiftNIO). It has no `RequestName` helper, so the
daemon calls `org.freedesktop.DBus.RequestName` itself to claim the name.

## Install (per user)

```sh
install -Dm755 linux/.build/release/topdrawerd ~/.local/bin/topdrawerd
install -Dm644 linux/systemd/topdrawerd.service ~/.config/systemd/user/topdrawerd.service
systemctl --user daemon-reload
systemctl --user enable --now topdrawerd
```

Check it: `systemctl --user status topdrawerd`. Stop/disable with
`systemctl --user disable --now topdrawerd`.

## Smoke test with `busctl`

With the daemon running (or `swift run --package-path linux topdrawerd` in another
terminal):

```sh
# Liveness:
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 Ping
#   s "topdrawerd 0.4.0 alive"

# The launcher document:
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 GetDocument

# Mounted volumes (JSON) and Trash state:
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 GetVolumes
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 GetTrashState
#   b u   false 2

# Eject a volume by its id (the mount point):
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 Eject s /media/$USER/MyStick

# A Recents/Fresh tab's live contents (JSON), by the tab's id from GetDocument:
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 GetRecents s <tab-uuid>

# Launch an item by its id (from GetDocument), open files with a specific app, reveal a file:
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 Launch s <item-uuid>
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 OpenWith sas org.gnome.gedit 1 file:///home/$USER/notes.txt
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 Reveal s file:///home/$USER/notes.txt

# The whole interface (all methods + the four change signals):
busctl --user introspect ch.lkmc.TopDrawer /ch/lkmc/TopDrawer

# Watch the change signals, then touch the launcher file / plug in a stick / trash a
# file / open a document (updates recently-used.xbel) / drop a file into ~/Downloads:
busctl --user monitor ch.lkmc.TopDrawer
```

## Tests

The unit tests cover the document source; the end-to-end tests export a real service
and call it over D-Bus, so they need a session bus:

```sh
dbus-run-session -- swift test --package-path linux
```

Plain `swift test --package-path linux` still runs the unit tests — the D-Bus tests
skip themselves when `DBUS_SESSION_BUS_ADDRESS` is unset. Linux CI runs the full set
under `dbus-run-session`.

## Scope / dependencies

LP-17 added the root **`MacDring`** package as a path dependency (`.package(path:
"..")`): the daemon consumes its `VolumeListing` / `TrashServicing` seams (LP-12) and
the `INotifyWatcher` copied there from PictKit. LP-18 also consumes MacDring's
`FreshScanner` / `RecentFileHit` / `FreshLister.scopes` (LP-08) and adds a **`CShims`**
C target (`linux/Sources/CShims/`) for the `statx` birth-time shim. `PictKit` (icon
rendering) is still not needed and stays deferred to the LP that wires icons.
