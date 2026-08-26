#define _GNU_SOURCE
#include "CShims.h"

#if defined(__linux__)
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>

int64_t topdrawer_file_btime(const char *path) {
    struct statx stx;
    memset(&stx, 0, sizeof(stx));
    /* AT_STATX_SYNC_AS_STAT: the same synchronization a plain stat() uses — good enough
     * for a birth time we only rank by. STATX_BTIME requests the creation time. */
    if (statx(AT_FDCWD, path, AT_STATX_SYNC_AS_STAT, STATX_BTIME, &stx) != 0) {
        return -1;
    }
    /* statx() can succeed without filling btime (the filesystem doesn't track it). */
    if (!(stx.stx_mask & STATX_BTIME)) {
        return -1;
    }
    /* Nanoseconds since the epoch, so files created within the same second still rank
     * correctly (a burst of downloads, an archive extraction). Fits int64_t until 2262;
     * the -1 sentinel is unambiguous since any real value is >= 0. */
    return (int64_t)stx.stx_btime.tv_sec * 1000000000LL + (int64_t)stx.stx_btime.tv_nsec;
}

#else

int64_t topdrawer_file_btime(const char *path) {
    (void)path;
    return -1;
}

#endif
