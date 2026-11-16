/* Copyright (c) 2026 kewe87. Licensed under LGPL-2.1-or-later.
 *
 * Tiny helper for build/preflight.sh: dlopen() a shared object with RTLD_NOW,
 * exactly the way GStreamer loads a plugin. Any undefined / wrong-version symbol
 * (e.g. a glibc symbol the target TV does not have) surfaces here as a load
 * failure, the same "undefined symbol ..." / "GLIBC_x.y not found" the TV would
 * print. Build for the target arch and run under qemu-user against a sysroot of
 * the target TV. */
#include <stdio.h>
#include <dlfcn.h>

int main(int argc, char **argv)
{
  void *h;
  if (argc < 2) {
    fprintf(stderr, "usage: %s <plugin.so>\n", argv[0]);
    return 2;
  }
  h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (h == NULL) {
    printf("LOAD FAILED: %s\n", dlerror());
    return 1;
  }
  printf("LOAD OK: %s\n", argv[1]);
  dlclose(h);
  return 0;
}
