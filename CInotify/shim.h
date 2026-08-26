#ifndef MACDRING_CINOTIFY_SHIM_H
#define MACDRING_CINOTIFY_SHIM_H

/* Exposes the inotify(7) syscalls (inotify_init1 / inotify_add_watch /
 * inotify_rm_watch) to the Swift INotifyWatcher on Linux — the daemon's
 * folder-tab and trash watches (LP-17), and later the recents/fresh watches
 * (LP-18).
 *
 * Deliberately just the header: the IN_* mask macros are NOT relied on from here
 * (Swift can't import C object-like macros as constants reliably) — they are
 * hard-coded in the Swift watcher — and `struct inotify_event`'s trailing flexible
 * array member is parsed by hand out of the read buffer rather than through the
 * imported struct. See docs/linux-port/implementation-plan.md Part 10.
 *
 * This mirrors PictKit's identical CInotify shim: the LP-05 watcher lives in the
 * other repo, and the root `MacDring` package has no PictKit dependency, so the
 * ~header + the watcher it feeds are deliberately duplicated here (see LP-17).
 *
 * Guarded on __linux__ so the module is empty (and harmless) if it is ever
 * modularised on a non-Linux host; on macOS the target isn't in the build graph at
 * all (the CInotify dependency is Linux-conditioned, and MacDring.xcodeproj never
 * resolves this SwiftPM manifest). */
#if defined(__linux__)
#include <sys/inotify.h>
#endif

#endif /* MACDRING_CINOTIFY_SHIM_H */
