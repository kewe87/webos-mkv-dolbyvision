#!/bin/bash
# Copyright (c) 2026 kewe87. Licensed under LGPL-2.1-or-later.
#
# Off-device load check for a plugin variant: does it actually load on the target
# TV's glibc and GStreamer? Runs the plugin through dlopen() (RTLD_NOW) under
# qemu-user against a sysroot of the target TV, so a glibc-version or ABI mismatch
# (the kind that makes the TV say "check failed") shows up here, on the PC, before
# anyone installs it. Build each variant and run this before every release.
#
# Usage:
#   build/preflight.sh <plugin.so> <gst_sysroot> [libc_sysroot]
#     gst_sysroot : dir with the target webOS version's GStreamer libs
#                   (usr/lib/libgst*), e.g. extracted from the TV firmware.
#     libc_sysroot: dir with the target glibc (lib/libc.so.6, ld-linux...).
#                   Defaults to gst_sysroot when it already contains a libc.
# Env:
#   QEMU_ARM      qemu-arm binary (auto-detected from the starfish SDK if unset).
#   STARFISH_SDK  SDK path for the cross compiler (default ~/tc/starfish).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=${1:?plugin.so required}
GSTSR=${2:?gst_sysroot required}
LIBCSR=${3:-$GSTSR}
SDK=${STARFISH_SDK:-$HOME/tc/starfish}

# cross compiler (for the tiny dlopen checker) + objdump
# shellcheck disable=SC1090
[ -z "${CC:-}" ] && . "$SDK"/environment-setup-* 2>/dev/null
QEMU=${QEMU_ARM:-$(command -v qemu-arm || echo "$SDK"/sysroots/x86_64-starfishsdk-linux/usr/bin/qemu-arm)}
[ -x "$QEMU" ] || { echo "qemu-arm not found (set QEMU_ARM)"; exit 3; }

echo "plugin:  $PLUGIN"
echo "max glibc required: $(objdump -T "$PLUGIN" 2>/dev/null | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2 -n | tail -1)"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
$CC "$HERE/dlopen-check.c" -o "$TMP/check" -ldl || { echo "could not build dlopen-check"; exit 3; }

ROOT="$TMP/root"; mkdir -p "$ROOT/lib" "$ROOT/usr/lib"
cp -a "$LIBCSR"/lib/*.so* "$ROOT/lib/" 2>/dev/null
cp -a "$GSTSR"/usr/lib/*.so* "$ROOT/usr/lib/" 2>/dev/null
# libz (demuxer dependency) from wherever it lives
find "$GSTSR" "$LIBCSR" -name 'libz.so*' -exec cp -a {} "$ROOT/usr/lib/" \; 2>/dev/null
echo "target glibc: $(readelf -V "$ROOT/lib/libc.so.6" 2>/dev/null | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2 -n | tail -1)  gst: $(ls "$ROOT"/usr/lib/libgstreamer-1.0.so.0.* 2>/dev/null | xargs -n1 basename | head -1)"

"$QEMU" -L "$ROOT" -E LD_LIBRARY_PATH=/usr/lib:/lib "$TMP/check" "$PLUGIN"
rc=$?
[ $rc -eq 0 ] && echo "PREFLIGHT: PASS" || echo "PREFLIGHT: FAIL"
exit $rc
