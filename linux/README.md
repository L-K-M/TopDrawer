# topdrawerd — the Top Drawer Linux daemon

`topdrawerd` is the background service behind Top Drawer's Linux frontend. It owns
the session-bus name **`ch.lkmc.TopDrawer`** and exports one object,
`/ch/lkmc/TopDrawer`, implementing the **`ch.lkmc.TopDrawer1`** interface. The
layer-shell frontend (LP-20+) talks to it over D-Bus; the macOS app is unaffected —
this package is built only on Linux.

LP-16 built the skeleton; **LP-17** added volumes + Trash; **LP-18** added the Recents
and Fresh tab contents (`GetRecents` + `RecentsChanged`); **LP-19** implemented launching
(`Launch` / `OpenWith` / `Reveal`) and records launches into the recents history;
**LP-19b** adds running-apps detection (`GetRunningAppIDs` + `RunningAppsChanged`);
**LP-20** adds the first frontend, **`topdrawer-shell`** — a GTK4 + layer-shell
"hello dock"; **LP-30** packages both as a **`.deb`** (see [Install from the
package](#install-from-the-deb-package)). Drop-to-tab (`AddDroppedURIs`) remains a
follow-up.

## `topdrawer-shell` — the layer-shell frontend (LP-20)

A minimal dock strip to prove the frontend stack: one undecorated GTK4 window,
anchored through **gtk4-layer-shell** to a configured screen edge (layer `top`, a
small margin, exclusive zone 0 — it reserves no screen space), showing the tab
titles from `GetDocument` and refreshing on `DocumentChanged`. Pointer enter/leave
and clicks are logged — the interaction probe the later UI LPs build on.

```sh
# Run it (on a layer-shell compositor: KDE Plasma 6, sway, hyprland, COSMIC…):
swift run --package-path linux topdrawer-shell -- --edge bottom [--monitor 0]
```

- **Runtime support**: any compositor implementing the wlr-layer-shell protocol.
  On **GNOME and X11 it exits with an error by design** (GNOME never adopted
  layer-shell; that tier is the LP-27 Shell extension).
- **Build dependencies**: `pkg-config`, `libgtk-4-dev`, and `gtk4-layer-shell`.
  Ubuntu packages the GTK4 binding only from **25.10** (`libgtk4-layer-shell-dev`);
  on older releases build it from source — Linux CI does exactly that, pinned to
  upstream tag `v1.3.0` (see `.github/workflows/linux-ci.yml`). CI only *builds* the
  shell (no compositor there); the D-Bus client (`TopDrawerShell`) is covered by
  tests under `dbus-run-session` like the daemon's.
- The GTK interop lives in the `topdrawer-shell` executable (C API, dexbar-pattern
  signal trampolines); everything bus-facing is in the GTK-free `TopDrawerShell`
  library so it stays testable without a display.

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
| `GetRunningAppIDs` | `() → s` | The running apps' desktop-file ids as JSON: `{"appIDs":["…"]}`, deduped and sorted (LP-19b). |
| `AddDroppedURIs` | `(s tabID, as uris) → b` | Stub — returns `false`; appending dropped files mutates the launcher document, which lands with the frontend's drag & drop (LP-23). |
| `DocumentChanged` | signal `()` | Emitted when the launcher file changes on disk (a modification-time watch). |
| `VolumesChanged` | signal `()` | Emitted when the set of mounted volumes changes (a `/proc` poll — inotify can't watch `/proc`) (LP-17). |
| `TrashChanged` | signal `()` | Emitted when the Trash contents change (an inotify watch on `Trash/files`) (LP-17). |
| `RecentsChanged` | signal `(s tabID)` | Emitted (per affected tab) when a Recents tab's source (`recently-used.xbel`) or a Fresh tab's landing zone changes (LP-18). |
| `RunningAppsChanged` | signal `()` | Emitted when the set of running apps changes (a `/proc` poll — inotify can't watch `/proc`) (LP-19b). |

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

- **Out of scope** (recorded follow-up): `AddDroppedURIs` (appending dropped files to a tab)
  awaits the launcher-document write path (LP-23).

### Running apps (LP-19b)

`GetRunningAppIDs` reports which applications are running so the frontend can draw a
running-app dot. On stock GNOME the Shell's introspection D-Bus is allow-listed away, so this
uses the documented fallback: every app is launched into a transient **systemd user scope**
named `app[-<launcher>]-<ApplicationID>[-<pid>|@<random>].scope`, which shows up in each
process's `/proc/<pid>/cgroup`. The daemon scans `/proc`, extracts the desktop-file id from
each `app-*.scope` (stripping the launcher prefix and the instance token, unescaping systemd's
`\x2d`), and returns the deduplicated, sorted set. `/proc` can't be inotify-watched, so a poll
(alongside the volumes poll) drives `RunningAppsChanged`.

The ids are returned as JSON (`{"appIDs":[…]}`), matching `GetVolumes`/`GetRecents` — a native
D-Bus `as` array is avoided because the D-Bus library signs an *empty* array as `ay`, not `as`,
which would break the (common) no-apps-running reply.

- **Out of scope** (recorded follow-ups): the exact GNOME-extension / KDE / wlroots
  running-app sources (`Shell.AppSystem`, plasma-window-management, foreign-toplevel) land
  with their respective frontends; matching scope ids against the installed `.desktop` set
  (to drop stray scopes) can reuse LP-19's `DesktopEntryScanner`.

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

Both executables answer `--version` and `--help` without touching the bus or a
display. Local builds report `0.0.0-dev`; the packaging below stamps the release
version (from the git tag) into `Sources/TopDrawerVersion/TopDrawerVersion.swift`
at build time, so the tag is the single source of truth — as it is for the macOS
`MARKETING_VERSION`.

## Install from the .deb package

Every [release](https://github.com/L-K-M/TopDrawer/releases) since 2.2.0 attaches
`TopDrawer-<version>-amd64.deb`, built on Ubuntu 24.04 (so it installs on 24.04 and
newer; `Depends` name the exact runtime libraries). It carries `/usr/bin/topdrawerd`,
`/usr/bin/topdrawer-shell`, the daemon's systemd **user** unit
(`/usr/lib/systemd/user/topdrawerd.service`), and a private copy of gtk4-layer-shell
under `/usr/lib/topdrawer/` — Ubuntu packages the GTK4 binding only from 25.10, so
the shell would otherwise not run on 24.04. Nothing is enabled automatically:

```sh
sudo apt install ./TopDrawer-<version>-amd64.deb
systemctl --user enable --now topdrawerd
topdrawerd --version
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 Ping
topdrawer-shell --edge bottom       # on a layer-shell compositor (see above)
```

Remove with `sudo apt remove topdrawer` (after `systemctl --user disable --now
topdrawerd`). The Swift runtime is linked statically, so the package depends on no
Swift installation.

To build the package yourself — `dpkg-dev`, `binutils` and (optionally) `lintian`
installed, gtk4-layer-shell built from source per the CI recipe in
`.github/actions/setup-gtk4-layer-shell/action.yml`:

```sh
linux/packaging/build-deb.sh 2.2.0               # → linux/.build/deb/topdrawer_2.2.0_amd64.deb
linux/packaging/build-deb.sh 2.2.0-beta.1 --output /tmp/TopDrawer-2.2.0-beta.1-amd64.deb
```

The script's header documents what it stages, how `Depends` are computed
(`dpkg-shlibdeps`), and the environment knobs (where the vendored library and its
license come from). The release workflow runs the same script, then installs the
result into a pristine `ubuntu:24.04` container and checks `--version` and a D-Bus
`Ping` before attaching it to the release.

## Seed a launcher document

Nothing on Linux creates the launcher document yet (the macOS app writes it; the
Linux write path arrives with drag & drop, LP-23), so a fresh install serves `{}` —
an empty dock with nothing to launch. Seed one by hand to have something to test.
The format is the macOS app's (`LauncherDocument`): every tab needs an `id` (a UUID)
and an `anchor`; items carry a `kind` and a `url`. Pick an application entry that
exists on your desktop (`ls /usr/share/applications`):

```sh
mkdir -p ~/.local/share/MacDring
cat > ~/.local/share/MacDring/launcher.json <<EOF
{
  "version": 1,
  "tabs": [
    {
      "id": "7B1E1B4A-0F7C-4D2E-9C3B-5A6D7E8F9A01",
      "title": "Apps",
      "kind": "items",
      "colorHex": "#0A84FF",
      "anchor": { "displayUUID": "00000000-0000-0000-0000-000000000000", "edge": "right", "position": 0.3, "order": 0 },
      "items": [
        { "id": "C0A1F2E3-1111-4222-8333-444455556661", "kind": "application", "displayName": "Text Editor",
          "url": "file:///usr/share/applications/org.gnome.TextEditor.desktop" },
        { "id": "C0A1F2E3-1111-4222-8333-444455556662", "kind": "folder", "displayName": "Downloads",
          "url": "file://$HOME/Downloads/" },
        { "id": "C0A1F2E3-1111-4222-8333-444455556663", "kind": "url", "displayName": "Top Drawer on GitHub",
          "url": "https://github.com/L-K-M/TopDrawer" }
      ]
    },
    {
      "id": "7B1E1B4A-0F7C-4D2E-9C3B-5A6D7E8F9A02",
      "title": "Fresh",
      "kind": "fresh",
      "colorHex": "#34C759",
      "anchor": { "displayUUID": "00000000-0000-0000-0000-000000000000", "edge": "right", "position": 0.5, "order": 1 },
      "items": []
    }
  ]
}
EOF
```

The daemon notices the file (`DocumentChanged`), `GetDocument` returns it verbatim,
the shell's strip shows `Apps · Fresh`, `Launch s C0A1F2E3-1111-4222-8333-444455556662`
opens Downloads in the file manager, and `GetRecents s 7B1E1B4A-0F7C-4D2E-9C3B-5A6D7E8F9A02`
lists the newest files in Downloads/Desktop/Documents. The `displayUUID` is a
placeholder: the Linux frontends don't place tabs yet (LP-21), and the macOS app
falls back to its main display for a UUID it doesn't know.

## Install (per user, from a local build)

Not if the `.deb` is installed: a unit in `~/.config/systemd/user/` overrides the
packaged one and would point at a binary the package doesn't install.

```sh
install -Dm755 linux/.build/release/topdrawerd ~/.local/bin/topdrawerd
install -Dm644 linux/systemd/topdrawerd.service ~/.config/systemd/user/topdrawerd.service
systemctl --user daemon-reload
systemctl --user enable --now topdrawerd
```

Check it: `systemctl --user status topdrawerd`. Stop/disable with
`systemctl --user disable --now topdrawerd`. The unit is tied to
`graphical-session.target` (started with the desktop, after it has exported
`DISPLAY`/`WAYLAND_DISPLAY` and friends to the user manager — the environment the
daemon's launches inherit — and stopped at logout), so `enable` takes effect at the
next graphical login; `--now` starts it in the current one.

## Smoke test with `busctl`

With the daemon running (or `swift run --package-path linux topdrawerd` in another
terminal):

```sh
# Liveness (the version is the package's — `0.0.0-dev` for a local build, the release
# version for one installed from the .deb; `topdrawerd --version` says the same):
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 Ping
#   s "topdrawerd 2.2.0 alive"

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

# The running apps' desktop-file ids (JSON):
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 GetRunningAppIDs
#   s "{\"appIDs\":[\"org.gnome.Nautilus\"]}"

# The whole interface (all methods + the five change signals):
busctl --user introspect ch.lkmc.TopDrawer /ch/lkmc/TopDrawer

# Watch the change signals, then touch the launcher file / plug in a stick / trash a
# file / open a document (updates recently-used.xbel) / drop a file into ~/Downloads:
busctl --user monitor ch.lkmc.TopDrawer
```

## Tests

The unit tests cover the document source; the end-to-end tests export a real service
and call it over D-Bus, so they need a **throwaway** session bus — never your
desktop's live one (the tests claim the daemon's well-known name, and on the real
bus they'd shadow or fight an actual topdrawerd):

```sh
dbus-run-session -- env TOPDRAWER_PRIVATE_TEST_BUS=1 swift test --package-path linux
```

Plain `swift test --package-path linux` always skips the D-Bus tests — they run only
when the `TOPDRAWER_PRIVATE_TEST_BUS` sentinel marks the bus as private (`DBUS_SESSION_BUS_ADDRESS`
being set is not enough; it is always set on a desktop). Linux CI runs the full set
under `dbus-run-session` with the sentinel.

## Scope / dependencies

LP-17 added the root **`MacDring`** package as a path dependency (`.package(path:
"..")`): the daemon consumes its `VolumeListing` / `TrashServicing` seams (LP-12) and
the `INotifyWatcher` copied there from PictKit. LP-18 also consumes MacDring's
`FreshScanner` / `RecentFileHit` / `FreshLister.scopes` (LP-08) and adds a **`CShims`**
C target (`linux/Sources/CShims/`) for the `statx` birth-time shim. `PictKit` (icon
rendering) is still not needed and stays deferred to the LP that wires icons.
