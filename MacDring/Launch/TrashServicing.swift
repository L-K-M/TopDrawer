import Foundation

/// The trash seam, named so a Linux backend has a shape to fill: how full the Trash is,
/// whether it's empty, moving files into it, and emptying it. On macOS this is the shape
/// of `TrashInspector` (count / empty check) plus `FileMover.trash` / `.emptyTrash`,
/// bundled by `SystemTrashService`. `TrashInspector` itself stays macOS-only (it reads
/// directory metadata via Darwin `getattrlist`), so only this shape is platform-neutral.
/// See PLAN.md §LP-12. `public` so the Linux `topdrawerd` package can provide its own
/// `gio`-backed conformer; every member is a standard-library type, so widening the
/// access level pulls no other type public and changes no macOS behavior.
public protocol TrashServicing {
    /// The total number of items across every Trash that "Empty Trash" would clear.
    func trashCount() -> Int
    /// Whether every such Trash is empty.
    func trashIsEmpty() -> Bool
    /// Moves `urls` (files only) to the Trash, recoverably; returns whether all succeeded.
    func trash(_ urls: [URL]) -> Bool
    /// Empties the Trash; returns whether it succeeded.
    func emptyTrash() -> Bool
}

#if os(macOS)
/// macOS `TrashServicing`: the existing `TrashInspector` metadata reads plus `FileMover`'s
/// recoverable move-to-Trash and Finder "Empty Trash". A pure wrapper — no behavior of
/// its own.
struct SystemTrashService: TrashServicing {
    func trashCount() -> Int { TrashInspector.trashCount() }
    func trashIsEmpty() -> Bool { TrashInspector.trashIsEmpty() }
    func trash(_ urls: [URL]) -> Bool { FileMover.trash(urls) }
    func emptyTrash() -> Bool { FileMover.emptyTrash() }
}
#endif
