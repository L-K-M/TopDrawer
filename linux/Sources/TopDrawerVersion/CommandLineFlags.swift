import Foundation

/// The `--version` / `--help` pre-scan both Linux executables run before anything else
/// (before the daemon touches the bus, before the shell calls `gtk_init`). One
/// implementation, so the `"<program> <version>"` line the Debian install smoke test
/// compares against the tag can't drift between the two binaries.
public enum CommandLineFlags {

    /// Prints `"<program> <version>"` for `--version`, or `usage` for `--help`/`-h`, and
    /// exits; returns when neither flag is present so the caller parses the rest.
    public static func exitOnVersionOrHelp(program: String, usage: String) {
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.contains("--version") {
            print("\(program) \(TopDrawerVersion.current)")
            exit(0)
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            exit(0)
        }
    }
}
