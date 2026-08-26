import TopDrawerDaemon

// `topdrawerd` is a thin shell over `TopDrawerDaemon`; all the logic lives in the
// library target so the tests can drive it. `Daemon.run()` never returns — it
// blocks on the session bus until SIGTERM/SIGINT.
#if os(Linux)
await Daemon.run()
#else
print("topdrawerd hosts Top Drawer's D-Bus service and runs on Linux only.")
#endif
