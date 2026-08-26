#ifndef TOPDRAWER_CSHIMS_H
#define TOPDRAWER_CSHIMS_H

#include <stdint.h>

/* The birth (creation) time of the file at `path`, in nanoseconds since the Unix epoch,
 * or -1 when the platform or filesystem doesn't provide it (then fall back to mtime —
 * see FreshScanner's ladder). Nanoseconds keep sub-second precision so same-second
 * files still rank correctly.
 *
 * Implemented with statx(STATX_BTIME) on Linux (glibc 2.28+/kernel 4.11+; noble ships
 * glibc 2.39), checking stx_mask & STATX_BTIME because not every filesystem records a
 * birth time even when statx() succeeds. A stub returning -1 elsewhere, so the module
 * still compiles on a non-Linux host (though the daemon only links it on Linux). See
 * docs/linux-port/implementation-plan.md Part 10. */
int64_t topdrawer_file_btime(const char *path);

#endif /* TOPDRAWER_CSHIMS_H */
