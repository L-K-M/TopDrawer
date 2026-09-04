import Foundation
import TopDrawerDaemon
import TopDrawerVersion

// `topdrawerd` is a thin shell over `TopDrawerDaemon`; all the logic lives in the
// library target so the tests can drive it. `Daemon.run()` never returns — it
// blocks on the session bus until SIGTERM/SIGINT.
//
// `--version` / `--help` answer before anything touches the bus: the Debian package's
// install smoke test runs `topdrawerd --version` in a container with no session bus,
// and a tester checking what is installed should not have to start the service.
CommandLineFlags.exitOnVersionOrHelp(
    program: "topdrawerd",
    usage: """
        usage: topdrawerd [--version] [--help]

        Top Drawer's Linux daemon: claims ch.lkmc.TopDrawer on the D-Bus session bus and
        serves the launcher document, volumes, Trash, recents, launching and running-app
        state to the frontends. Runs until SIGTERM/SIGINT — see linux/README.md.
        """)

#if os(Linux)
await Daemon.run()
#else
print("topdrawerd hosts Top Drawer's D-Bus service and runs on Linux only.")
#endif
