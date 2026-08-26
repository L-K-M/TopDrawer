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
    return (int64_t)stx.stx_btime.tv_sec;
}

#else

int64_t topdrawer_file_btime(const char *path) {
    (void)path;
    return -1;
}

#endif
