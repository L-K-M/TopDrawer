#if os(Linux)
import Foundation

/// Minimal synchronous subprocess helper for the small CLI tools the daemon shells out
/// to (`gio`, `udisksctl`). Looks the binary up on `PATH` via `/usr/bin/env` so it
/// works regardless of where the distro installs them.
enum LinuxProcess {

    /// Runs `tool args…` to completion. Returns the exit status (or -1 if it couldn't be
    /// launched) and captured stdout/stderr. Never throws — a missing tool is a failed
    /// status, which the callers treat as "couldn't do it".
    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        // Read before waiting so a tool that fills the pipe buffer can't deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// `true` when `tool args…` exits 0.
    static func succeeds(_ tool: String, _ args: [String]) -> Bool {
        run(tool, args).status == 0
    }
}
#endif
