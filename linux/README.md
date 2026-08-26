# topdrawerd — the Top Drawer Linux daemon

`topdrawerd` is the background service behind Top Drawer's Linux frontend. It owns
the session-bus name **`ch.lkmc.TopDrawer`** and exports one object,
`/ch/lkmc/TopDrawer`, implementing the **`ch.lkmc.TopDrawer1`** interface. The
layer-shell frontend (LP-20+) talks to it over D-Bus; the macOS app is unaffected —
this package is built only on Linux.

This is the **LP-16 skeleton**: the D-Bus surface, a systemd user unit, and CI. It
serves the launcher document verbatim and stubs the launch/drop methods; later LPs
fill them in (see the plan's LP-17 – LP-19).

## The interface (`ch.lkmc.TopDrawer1`)

| Member | Signature | LP-16 behavior |
| --- | --- | --- |
| `Ping` | `() → s` | Returns `topdrawerd <version> alive` — the liveness smoke test. |
| `GetDocument` | `() → s` | The launcher JSON (`$XDG_DATA_HOME/MacDring/launcher.json`), served verbatim; `{}` if absent. |
| `Launch` | `(s itemID) → b` | Stub — returns `false` (real launching lands in LP-19). |
| `AddDroppedURIs` | `(s tabID, as uris) → b` | Stub — returns `false` (drops land in LP-17). |
| `DocumentChanged` | signal `()` | Emitted when the launcher file changes on disk (a modification-time watch). |

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
#   s "topdrawerd 0.1.0 alive"

# The launcher document:
busctl --user call ch.lkmc.TopDrawer /ch/lkmc/TopDrawer ch.lkmc.TopDrawer1 GetDocument

# The whole interface (methods + the DocumentChanged signal):
busctl --user introspect ch.lkmc.TopDrawer /ch/lkmc/TopDrawer

# Watch the change signal, then touch the launcher file in another terminal:
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

Per the port plan, this package will also depend on the root `MacDring` package
(`.package(path: "..")`) and `PictKit` (via its Git URL) once the daemon consumes
their APIs — the document/lister types in `MacDring` are still module-internal, and
icon rendering isn't wired yet. Those dependencies land with LP-17, the first daemon
features that need them, keeping this skeleton's dependency and build surface to what
it actually uses.
