import Foundation
#if os(Linux)
import DBUS
import Logging
import Glibc
#endif

/// Process-level entry point for `topdrawerd`: connect to the session bus, export
/// the service, and run until signalled. Split from `TopDrawerService` (which is
/// connection-scoped and unit-testable) so the executable stays a thin shell.
public enum Daemon {

    #if os(Linux)
    /// Connects to the session bus, exports `ch.lkmc.TopDrawer`, and blocks until the
    /// process receives SIGTERM/SIGINT (systemd stop, or Ctrl-C). Never returns
    /// normally; exits the process on a fatal startup error.
    public static func run(source: LauncherDocumentSource = .default()) async {
        // An immutable copy so the SwiftNIO closure below can capture it without the
        // Swift 6 "captured var" concurrency warning.
        let logger: Logger = {
            var logger = Logger(label: "topdrawerd")
            logger.logLevel = .info
            return logger
        }()
        installSignalHandlers()

        do {
            try await DBusClient.withSessionBus(
                auth: .external(userID: String(getuid())),
                logger: logger
            ) { connection in
                let service = TopDrawerService(source: source, logger: logger)
                try await service.run(on: connection)
                logger.info("topdrawerd ready on \(TopDrawerService.busName); serving \(source.url.path)")
                await blockUntilSignalled()
            }
        } catch {
            logger.critical("topdrawerd failed to start: \(error)")
            exit(1)
        }
    }

    /// Exit cleanly on the signals systemd and terminals use to stop us. The daemon
    /// holds no unflushed state (the app owns the launcher file), so a plain exit is
    /// enough; systemd escalates to SIGKILL if we ever hang.
    private static func installSignalHandlers() {
        signal(SIGTERM) { _ in exit(0) }
        signal(SIGINT) { _ in exit(0) }
    }

    /// Blocks the connection scope forever; the process leaves via a signal handler
    /// (which `exit`s). A plain sleep loop rather than a never-resumed continuation,
    /// which the runtime flags as a "continuation misuse" leak when the process exits.
    private static func blockUntilSignalled() async {
        while true {
            try? await Task.sleep(for: .seconds(3600))
        }
    }
    #endif
}
