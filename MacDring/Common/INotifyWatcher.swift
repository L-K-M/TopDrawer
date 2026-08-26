#if os(Linux)
import Foundation
import Glibc
import MacDringCInotify

/// Watches a single directory and calls `onChange` (coalesced, on the main queue)
/// whenever its contents change — the Linux stand-in for the FSEvents/`DispatchSource`
/// directory watches the daemon needs for folder-tab and Trash tracking (LP-17), and
/// later for the recents file and fresh scopes (LP-18).
///
/// **Deliberate duplication.** This is a near-verbatim copy of PictKit's
/// `IconStoreWatcher` (its LP-05 inotify wrapper), generalised to a bare
/// `(directory, onChange)` contract. The wrapper lives in PictKit, and the root
/// `MacDring` package has no PictKit dependency, so — as LP-17 mandates — the ~100
/// lines are copied here rather than introducing a dependency for one file. Fixes to
/// the inotify plumbing should be mirrored across both copies.
///
/// **inotify rather than a `DispatchSource` file-object source on the directory.**
/// Apps write files atomically (temp-file-plus-rename), so an object source armed on a
/// single descriptor stops watching the file that matters. inotify watches the
/// *directory* by path and reports the create/close/rename/delete a write produces.
///
/// Two details the plan pins (Part 10): the `IN_*` masks are hard-coded, because Swift
/// can't import the C object-like macros as constants reliably; and
/// `struct inotify_event`'s trailing flexible array member is parsed by hand out of
/// the read buffer rather than through the imported struct.
public final class INotifyWatcher {

    /// How long to coalesce a burst of events before delivering one `onChange`. Valued
    /// to match the macOS FSEvents latency, so the two platforms behave the same from a
    /// caller's point of view.
    public static let latency: TimeInterval = 0.2

    // Hard-coded inotify event masks (see the type note above).
    private enum Mask {
        static let create: UInt32     = 0x0000_0100  // IN_CREATE
        static let delete: UInt32     = 0x0000_0200  // IN_DELETE
        static let movedTo: UInt32    = 0x0000_0080  // IN_MOVED_TO
        static let movedFrom: UInt32  = 0x0000_0040  // IN_MOVED_FROM
        static let closeWrite: UInt32 = 0x0000_0008  // IN_CLOSE_WRITE
        static let moveSelf: UInt32   = 0x0000_0800  // IN_MOVE_SELF
    }
    /// What a settled directory is watched for: any write another app makes. MOVED_FROM
    /// as well as MOVED_TO, so a file renamed *out* notifies just like an unlink
    /// (DELETE); MOVE_SELF so the whole directory being renamed away is noticed (the
    /// path stops resolving → re-arm).
    private static let directoryMask = Mask.create | Mask.movedTo | Mask.delete
                                     | Mask.closeWrite | Mask.movedFrom | Mask.moveSelf
    /// What a not-yet-existing directory's parent is watched for, to catch it appear.
    private static let parentMask = Mask.create | Mask.movedTo
    /// How long to wait before retrying a failed watch — the path may not exist yet on a
    /// fresh machine, where FSEvents would watch it natively.
    private static let retryInterval: TimeInterval = 5.0

    private let directory: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "ch.lkmc.topdrawer.inotify-watcher", qos: .utility)
    private let fileManager = FileManager.default

    // All of the following are touched only on `queue`.
    private var fd: Int32 = -1
    private var watch: Int32 = -1
    /// True while we're watching the parent because `directory` doesn't exist yet.
    private var watchingParent = false
    private var source: DispatchSourceRead?
    private var debounce: DispatchWorkItem?
    private var started = false

    /// - Parameters:
    ///   - directory: the directory watched. It need not exist yet — the watcher tracks
    ///     the parent until it appears, then re-arms on it.
    ///   - onChange: called on the main queue after a coalesced burst of changes.
    public init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    // `stop()`'s `queue.sync` in deinit is safe only because no closure submitted to
    // `queue` releases the last reference to `self` on the queue: the event, cancel and
    // retry handlers capture `self` weakly, and the debounce item — which needs a strong
    // `self` to clear `debounce` — hands that strong `self` to a main-queue block before
    // returning, so its final release lands on main, not here. Preserve that when adding
    // queue work.
    deinit { stop() }

    /// Starts watching. Safe to call twice; the second call does nothing.
    ///
    /// Watching a directory that does not exist yet is a normal case (a Trash that has
    /// never been used, a folder tab pointed at a not-yet-created path). We watch the
    /// parent until the directory appears, then re-arm on it (`armWatch`).
    public func start() {
        queue.sync {
            guard !started else { return }
            let descriptor = inotify_init1(O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else {
                NSLog("INotifyWatcher: couldn't start inotify; changes to \(directory.path) "
                      + "will not be observed until relaunch.")
                return
            }
            fd = descriptor
            started = true
            armWatch()

            // The cancel handler owns the descriptor by value, so the fd is always
            // closed on stop()/deinit even if `self` is already gone.
            let owned = descriptor
            let readSource = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            readSource.setEventHandler { [weak self] in self?.drain() }
            readSource.setCancelHandler { close(owned) }
            source = readSource
            readSource.resume()
        }
    }

    public func stop() {
        queue.sync {
            guard started else { return }
            started = false
            debounce?.cancel()
            debounce = nil
            if let source {
                source.cancel()      // the cancel handler closes the descriptor
                self.source = nil
            } else if fd >= 0 {
                close(fd)
            }
            fd = -1
            watch = -1
            watchingParent = false
        }
    }

    // MARK: inotify plumbing (all on `queue`)

    /// The single re-arm primitive: watch `directory` if it exists, else its parent so
    /// we notice it appear. Drops any previous watch first (a re-arm across a
    /// delete/recreate or a rename-away would otherwise leak the old descriptor, which
    /// keeps following the moved inode). `watchingParent` flips only on success, and a
    /// failed `add_watch` — the path doesn't exist yet, even the parent — schedules a
    /// retry rather than leaving the watcher silent.
    private func armWatch() {
        guard fd >= 0 else { return }
        if watch >= 0 { inotify_rm_watch(fd, watch); watch = -1 }
        let exists = directoryExists(directory)
        let target = exists ? directory : directory.deletingLastPathComponent()
        let mask = exists ? Self.directoryMask : Self.parentMask
        let descriptor = target.path.withCString { inotify_add_watch(fd, $0, mask) }
        guard descriptor >= 0 else {
            NSLog("INotifyWatcher: couldn't watch \(target.path) yet; retrying.")
            queue.asyncAfter(deadline: .now() + Self.retryInterval) { [weak self] in
                guard let self, self.started else { return }
                self.armWatch()
            }
            return
        }
        watch = descriptor
        watchingParent = !exists
    }

    /// Reads every pending event (the fd is non-blocking) and, if any of them matter,
    /// schedules the debounced notify.
    private func drain() {
        guard fd >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var directoryAppeared = false
        var sawChange = false
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count == -1, errno == EINTR { continue }   // interrupted by a signal; retry
            if count <= 0 { break }                        // 0 or -1/EAGAIN once drained
            parse(buffer, count: count, directoryAppeared: &directoryAppeared, change: &sawChange)
        }
        if watchingParent, directoryAppeared {
            armWatch()                // the directory appeared → watch it directly
            sawChange = true          // it just appeared; treat it as a change
        } else if !watchingParent, !directoryExists(directory) {
            // The watched directory was deleted or renamed away: the kernel drops the
            // watch (IN_DELETE_SELF/IN_IGNORED) or the path stops resolving (MOVE_SELF).
            // Re-arm on the parent — as at first run — so a recreated directory is
            // noticed rather than going silent; it vanishing is itself a change.
            armWatch()
            sawChange = true
        }
        if sawChange { scheduleNotify() }
    }

    /// Walks the inotify event buffer by hand: a 16-byte header (wd, mask, cookie, len)
    /// then `len` name bytes, repeated. In parent mode only the watched directory
    /// appearing counts; once watching the directory itself, every event counts.
    private func parse(_ buffer: [UInt8], count: Int,
                       directoryAppeared: inout Bool, change: inout Bool) {
        let wantedName = directory.lastPathComponent
        buffer.withUnsafeBufferPointer { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + 16 <= count {
                let mask = Self.readUInt32(base, offset + 4)
                let length = Int(Self.readUInt32(base, offset + 12))
                let nameStart = offset + 16
                if watchingParent {
                    if length > 0, nameStart + length <= count,
                       mask & (Mask.create | Mask.movedTo) != 0,
                       Self.name(base, at: nameStart, maxLength: length) == wantedName {
                        directoryAppeared = true
                    }
                } else {
                    change = true
                }
                offset = nameStart + length
            }
        }
    }

    /// Coalesce a burst into one delivery, anchoring the window at its *first* event —
    /// FSEvents' latency semantics. Re-anchoring on every event (cancel + reschedule)
    /// would let a steady stream of writes postpone the notification forever; instead,
    /// once a window is open we fold later events into it and open the next only after
    /// this one fires. The work item clears `debounce` on `queue` before delivering, so
    /// a following burst starts a fresh window. It captures `self` weakly and, while
    /// running, hands a strong `self` to the main-queue block — so it never releases the
    /// last reference on `queue` (see the invariant noted above `deinit`).
    private func scheduleNotify() {
        guard debounce == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.debounce = nil
            DispatchQueue.main.async { self.onChange() }
        }
        debounce = item
        queue.asyncAfter(deadline: .now() + Self.latency, execute: item)
    }

    // MARK: Byte helpers

    /// Little-endian `UInt32` at `index` — inotify's buffer is host-endian, and the
    /// supported hosts (x86_64, aarch64) are little-endian. Read byte-wise so an
    /// unaligned offset can't trap.
    private static func readUInt32(_ p: UnsafePointer<UInt8>, _ index: Int) -> UInt32 {
        UInt32(p[index]) | (UInt32(p[index + 1]) << 8)
            | (UInt32(p[index + 2]) << 16) | (UInt32(p[index + 3]) << 24)
    }

    /// The NUL-terminated name inside an event's `len`-byte name field.
    private static func name(_ p: UnsafePointer<UInt8>, at start: Int, maxLength: Int) -> String {
        var bytes = [UInt8]()
        var i = 0
        while i < maxLength, p[start + i] != 0 {
            bytes.append(p[start + i])
            i += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
#endif
