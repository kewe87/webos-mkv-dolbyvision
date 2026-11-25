#!/bin/bash
# Builds LG's webOS 25 GStreamer 1.24.0 core + plugins-base (libraries only) for
# 32-bit ARM into a starfish SDK 9.0.0 target sysroot, so libgstmatroska can be
# compiled/linked against the real webOS 25 headers+libs and qemu-checked.
# Only LG's TARGET deps (lib32-recipe-sysroot-gstcore) are used; LG's native deps
# break the SDK's own python/meson, so the host meson/ninja are used instead.
# Usage: LG_GST=<dir with lib32-recipe-sysroot-gstcore.tar.gz> SDK_INSTALLER=<starfish-sdk-...-9.0.0.sh>
#        GST_SRC=<extracted gstreamer_open_source.tar.gz>/gstreamer  ports/webos25/build-gst.sh
set -e
D=${LG_GST:?set LG_GST}
SDKI=${SDK_INSTALLER:?set SDK_INSTALLER}
SDK=${STARFISH_SDK:-$HOME/tc/starfish9}
G=${GST_SRC:?set GST_SRC}/subprojects
if [ ! -f $SDK/.lg-gst-deps ]; then
  rm -rf $SDK; sh $SDKI -y -d $SDK >/dev/null
  tar xzf $D/lib32-recipe-sysroot-gstcore.tar.gz -C $SDK/sysroots/ca9v1-starfishmllib32-linux-gnueabi
  touch $SDK/.lg-gst-deps
fi
. $SDK/environment-setup-ca9v1-starfishmllib32-linux-gnueabi >/dev/null 2>&1
S=$SDKTARGETSYSROOT
# glib tool variables in LG's .pc files resolve into the sysroot: point them at the host tools
mkdir -p $S/usr/bin
for t in glib-mkenums glib-genmarshal glib-compile-resources glib-compile-schemas gdbus-codegen; do
  [ -x /usr/bin/$t ] && ln -sf /usr/bin/$t $S/usr/bin/$t
done
TB=$OECORE_NATIVE_SYSROOT/usr/bin/arm-starfishmllib32-linux-gnueabi
X=$SDK/arm.cross
cat > $X <<EOC
[binaries]
c = ['$TB/arm-starfishmllib32-linux-gnueabi-gcc', '-march=armv7-a', '-mfloat-abi=softfp', '-mfpu=neon', '--sysroot=$S']
cpp = ['$TB/arm-starfishmllib32-linux-gnueabi-g++', '-march=armv7-a', '-mfloat-abi=softfp', '-mfpu=neon', '--sysroot=$S']
ar = '$TB/arm-starfishmllib32-linux-gnueabi-ar'
strip = '$TB/arm-starfishmllib32-linux-gnueabi-strip'
pkg-config = '/usr/bin/pkg-config'
[properties]
sys_root = '$S'
pkg_config_libdir = '$S/usr/lib/pkgconfig:$S/usr/share/pkgconfig'
[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
EOC
unset CC CXX CFLAGS CXXFLAGS LDFLAGS CPPFLAGS PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR
export PKG_CONFIG_SYSROOT_DIR=$S
# host meson/ninja/python first; flex/bison/m4 from the SDK (not in WSL)
HT=$SDK/hosttools; mkdir -p $HT
for t in flex bison m4; do ln -sf $OECORE_NATIVE_SYSROOT/usr/bin/$t $HT/$t; done
export PATH=/usr/bin:/bin:$HT
cd $G/gstreamer; rm -rf b
/usr/bin/meson setup b --cross-file $X -Dprefix=/usr -Dlibdir=lib -Dexamples=disabled -Dtests=disabled \
  -Dbenchmarks=disabled -Dtools=disabled -Dintrospection=disabled -Ddoc=disabled -Dcheck=disabled \
  -Dlibunwind=disabled -Dlibdw=disabled -Dptp-helper=disabled -Dbash-completion=disabled -Dnls=disabled
ninja -C b; DESTDIR=$S ninja -C b install >/dev/null
cd $G/gst-plugins-base; rm -rf b
/usr/bin/meson setup b --cross-file $X -Dprefix=/usr -Dlibdir=lib -Dauto_features=disabled -Dexamples=disabled \
  -Dtests=disabled -Dtools=disabled -Dintrospection=disabled -Ddoc=disabled -Dnls=disabled -Dorc=disabled
ninja -C b; DESTDIR=$S ninja -C b install >/dev/null
ls $S/usr/lib/libgst{reamer,base,video,audio,pbutils,riff,tag}-1.0.so.0.*
