#!/bin/bash
# Builds libgstmatroska.so for LG webOS 24 (webOS 9, GStreamer 1.18.5.1, 32-bit ARM, glibc 2.31)
# from LG's 1.18.5.1 matroska source + our DV patch.
# LG's webOS 24 "target sysroot" deps are x86-64 host builds, so: LG 1.18.5 HEADERS
# (arch-independent) first, then the webOS 22 starfish SDK 7.0.0 sysroot (ARM glib,
# ARM GStreamer 1.18 libs with identical sonames) for glibconfig.h and linking.
# Usage: ports/webos24/build.sh [output.so]
#   MATROSKA_SRC  LG's gst-plugins-good/gst/matroska (1.18.5.1, from "gst_source_webos9.0.0.zip"
#                 in LG's "webOS24 WG 4.0" package) with 0001-webos24-matroska-dolby-vision.patch applied
#   GSTINC        LG's 1.18.5 headers: usr/include/gstreamer-1.0 from ca9v1_toolchain_dep_webos9.0.0.tar.gz
#   STARFISH_SDK  starfish SDK 7.0.0 (as for webOS 22)
set -e
P=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$P/../.." && pwd)
SRC=${MATROSKA_SRC:?set MATROSKA_SRC}
GSTINC=${GSTINC:?set GSTINC}
OUT=${1:-$REPO/out/plugins/gst-1.18.5/libgstmatroska.so}
DOVI_LIB=$REPO/out/libdovi/libdolby_vision.a
. ${STARFISH_SDK:-$HOME/tc/starfish}/environment-setup-ca9v1-starfishmllib32-linux-gnueabi >/dev/null 2>&1
S=$SDKTARGETSYSROOT
mkdir -p "$(dirname "$OUT")"; OBJ=$(mktemp -d); trap 'rm -rf "$OBJ"' EXIT
CF="-I$SRC -I$P -I$GSTINC -I$S/usr/include/glib-2.0 -I$S/usr/lib/glib-2.0/include \
 -pipe -D_FILE_OFFSET_BITS=64 -Wall -O2 -g -fvisibility=hidden -fno-strict-aliasing -DG_DISABLE_CAST_CHECKS \
 -Wno-multichar -Wpointer-arith -feliminate-unused-debug-types -fPIC -pthread -DHAVE_CONFIG_H"
for f in ebml-read ebml-write matroska matroska-demux matroska-parse matroska-ids matroska-mux matroska-read-common webm-mux lzo; do
  $CC $CF -c "$SRC/$f.c" -o "$OBJ/$f.o"
done
$CC $CF -c "$REPO/src/matroska/glibc-compat.c" -o "$OBJ/glibc-compat.o"
$CC -shared -fPIC $LDFLAGS -Wl,-soname,libgstmatroska.so -Wl,--no-undefined -o "$OUT" "$OBJ"/*.o \
  "$DOVI_LIB" -Wl,--exclude-libs,ALL -Wl,--gc-sections -lpthread -ldl -lgcc_s \
  -lgstpbutils-1.0 -lgstaudio-1.0 -lgstriff-1.0 -lgstvideo-1.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0 \
  -lgobject-2.0 -lglib-2.0 -lz -lbz2 -lm
$STRIP --strip-debug "$OUT"
echo "Built: $OUT"; file "$OUT" | cut -d: -f2; sha256sum "$OUT"; md5sum "$OUT"
