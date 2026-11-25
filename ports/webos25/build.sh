#!/bin/bash
# Builds libgstmatroska.so for LG webOS 25 (GStreamer 1.24.0, 32-bit ARM, glibc 2.35)
# from LG's 1.24.0 matroska source (which already does Dolby Vision for profiles
# 4/5/8/9/10) + our profile 7 -> 8.1 conversion. Needs build-gst-1.24.sh first.
# Usage: ports/webos25/build.sh [output.so]   (run build-gst.sh first)
#   MATROSKA_SRC  LG's gst-plugins-good/gst/matroska (1.24.0, from gstreamer_open_source.zip in LG's
#                 "webOS25 WG ReNew" package, same as github.com/lgstreamer/gstreamer-webos-25)
#                 with 0001-webos25-matroska-p7-to-p81.patch applied (or: apply-p7.py)
#   STARFISH_SDK  starfish SDK 9.0.0 prepared by build-gst.sh
set -e
P=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$P/../.." && pwd)
SRC=${MATROSKA_SRC:?set MATROSKA_SRC}
OUT=${1:-$REPO/out/plugins/gst-1.24.0/libgstmatroska.so}
DOVI_LIB=$REPO/out/libdovi/libdolby_vision.a
. ${STARFISH_SDK:-$HOME/tc/starfish9}/environment-setup-ca9v1-starfishmllib32-linux-gnueabi >/dev/null 2>&1
S=$SDKTARGETSYSROOT
mkdir -p "$(dirname "$OUT")"; OBJ=$(mktemp -d); trap 'rm -rf "$OBJ"' EXIT
CF="-I$SRC -I$P -I$S/usr/include/gstreamer-1.0 -I$S/usr/include/glib-2.0 -I$S/usr/lib/glib-2.0/include \
 -pipe -D_FILE_OFFSET_BITS=64 -Wall -O2 -g -fvisibility=hidden -fno-strict-aliasing -DG_DISABLE_CAST_CHECKS \
 -Wno-multichar -Wpointer-arith -feliminate-unused-debug-types -fPIC -pthread -DHAVE_CONFIG_H"
for f in ebml-read ebml-write gstmatroskaelement matroska matroska-demux matroska-parse matroska-ids matroska-mux matroska-read-common webm-mux lzo; do
  $CC $CF -c "$SRC/$f.c" -o "$OBJ/$f.o"
done
$CC $CF -c "$REPO/src/matroska/glibc-compat.c" -o "$OBJ/glibc-compat.o"
$CC -shared -fPIC $LDFLAGS -Wl,-soname,libgstmatroska.so -Wl,--no-undefined -o "$OUT" "$OBJ"/*.o \
  "$DOVI_LIB" -Wl,--exclude-libs,ALL -Wl,--gc-sections -lpthread -ldl -lgcc_s \
  -lgstpbutils-1.0 -lgstaudio-1.0 -lgstriff-1.0 -lgstvideo-1.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0 \
  -lgobject-2.0 -lglib-2.0 -lz -lbz2 -lm
$STRIP --strip-debug "$OUT"
echo "Built: $OUT"; file "$OUT" | cut -d: -f2 | cut -c1-70; sha256sum "$OUT"
