/* Copyright (c) 2026 kewe87. Licensed under LGPL-2.1-or-later.
 *
 * Provide statx() and gettid() via raw syscalls. The statically linked Rust
 * libdovi (profile 7 -> 8.1 conversion) otherwise imports statx@GLIBC_2.28 and
 * gettid@GLIBC_2.30, which makes the plugin fail to load on the older glibc of
 * webOS 6 / webOS 5 (glibc 2.28) with "version `GLIBC_2.30' not found". Defining
 * them in the plugin itself removes those versioned imports. The symbols are
 * hidden, so they only satisfy libdovi's own references at link time and never
 * affect the rest of the process; on newer glibc (webOS 22) this is a harmless
 * shadow - same syscall, same result. */
#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/types.h>

#ifndef SYS_statx
#define SYS_statx 397   /* __NR_statx on arm (EABI) */
#endif
#ifndef SYS_gettid
#define SYS_gettid 224  /* __NR_gettid on arm (EABI) */
#endif

__attribute__((used))
int statx(int dirfd, const char *path, int flags, unsigned int mask, void *buf)
{
  return (int) syscall(SYS_statx, dirfd, path, flags, mask, buf);
}

__attribute__((used))
pid_t gettid(void)
{
  return (pid_t) syscall(SYS_gettid);
}
