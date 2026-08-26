# topdrawerd — the Top Drawer Linux daemon

`topdrawerd` is the background service behind Top Drawer's Linux frontend. It owns
the session-bus name **`ch.lkmc.TopDrawer`** and exports one object,
`/ch/lkmc/TopDrawer`, implementing the **`ch.lkmc.TopDrawer1`** interface. The
layer-shell frontend (LP-20+) talks to it over D-Bus; the macOS app is unaffected —
this package is built only on Linux.

LP-16 built the skeleton (the D-Bus surface, a systemd user unit, and CI). **LP-17**
adds the volumes and Trash surface: mounted-volume listing + eject, and Trash state,
with change signals. The launch/drop methods are still stubs; later LPs fill them in
(see the plan's LP-18 – LP-19).

## The interface (`ch.lkmc.TopDrawer1`)

| Member | Signature | Behavior |
| --- | --- | --- |
| `Ping` | `() → s` | Returns `topdrawerd <version> alive` — the liveness smoke test. |
| `GetDocument` | `() → s` | The launcher JSON (`$XDG_DATA_HOME/MacDring/launcher.json`), served verbatim; `{}` if absent. |
| `GetVolumes` | `() → s` | The classified mounted volumes as JSON: `{"volumes":[{"id","name","path","kind","device","ejectable"}]}`, `kind` ∈ `disk`/`network`/`cloud` (LP-17). |
| `Eject` | `(s volumeID) → b` | Unmounts/powers off the volume with that `id` (its mount point); `false` if unknown or it failed (LP-17). |
| `GetTrashState` | `() → b u` | Whether the Trash is empty, and its item count (LP-17). |
| `Launch` | `(s itemID) → b` | Stub — returns `false` (real launching lands in LP-19). |
| `AddDroppedURIs` | `(s tabID, as uris) → b` | Stub — returns `false` (drops land in LP-19). |
| `DocumentChanged` | signal `()` | Emitted when the launcher file changes on disk (a modification-time watch). |
| `VolumesChanged` | signal `()` | Emitted when the set of mounted volumes changes (a `/proc` poll — inotify can't watch `/proc`) (LP-17). |
| `TrashChanged` | signal `()` | Emitted when the Trash contents change (an inotify watch on `Trash/files`) (LP-17). |

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
#   s "topdrawerd 0.2.0 alive"

# The launcher document:
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 GetDocument

# Mounted volumes (JSON) and Trash state:
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 GetVolumes
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 GetTrashState
#   b u   false 2

# Eject a volume by its id (the mount point):
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 Eject s /media/$USER/MyStick

# The whole interface (methods + the DocumentChanged/VolumesChanged/TrashChanged signals):
busctl --user introspect ch.lkmc.TopDrawer /ch/lkmc/TopDrawer

# Watch the change signals, then touch the launcher file / plug in a stick / trash a file:
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

LP-17 adds the root **`MacDring`** package as a path dependency (`.package(path:
"..")`): the daemon consumes its `VolumeListing` / `TrashServicing` seams (LP-12) and
the `INotifyWatcher` copied there from PictKit. `PictKit` (icon rendering) is still not
needed and stays deferred to the LP that wires icons.
