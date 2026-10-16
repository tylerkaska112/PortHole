#!/bin/bash
# Recreate the "base" libwineserver.a that build/wineserver/build.sh expects to start from (it only swaps ~23 patched objects into an existing archive,
# and the repo does not track that archive). The base objects are Wine's own server/*.c compiled with the same flags build.sh uses; the files below are
# the ones build.sh does NOT replace (derived from the old archive's object list minus build.sh's REPLACEMENTS). Vendor tree stays unmodified.
set -eu
R="${MADEIRA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../vendor/Madeira" && pwd)}"
WINE_SRC="$R/wine"; BUILD_DIR="$R/build/wineserver"; SHIMS_DIR="$R/build/ntdll-unix/shims"
SDK=$(xcrun --sdk iphoneos --show-sdk-path); OBJ="$BUILD_DIR/obj"; mkdir -p "$OBJ"
FLAGS=(-arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 -O2
  -I"$WINE_SRC/include" -I"$WINE_SRC/include/wine" -I"$WINE_SRC/build-macos/include" -I"$BUILD_DIR" -I"$WINE_SRC/server" -I"$SHIMS_DIR"
  -I"$BUILD_DIR/../madsync" -DHAVE_LINUX_NTSYNC_H=1
  -include "$BUILD_DIR/config_ios.h" -include stdarg.h -include "$BUILD_DIR/unicode_fix.h" -include "$BUILD_DIR/wineserver_ios_kill.h"
  -DBINDIR=\"/usr/local/bin\" -DDATADIR=\"/usr/local/share\" -D__WINESRC__ -DWINE_IOS=1 -Dmain=wineserver_main -Wno-implicit-function-declaration)
BASE="atom change clipboard completion console d3dkmt debugger device directory file hook mailslot mutex named_pipe procfs ptrace registry serial signal symlink timer token trace"
rm -f "$OBJ/libwineserver.a"; ok=0; bad=""
for n in $BASE; do
  if xcrun -sdk iphoneos clang "${FLAGS[@]}" -c "$WINE_SRC/server/$n.c" -o "$OBJ/$n.o" 2>"$OBJ/err-$n.txt"; then ok=$((ok+1)); else bad="$bad $n"; fi
done
echo "base objects: $ok ok, failed:${bad:- none}"
[ -z "$bad" ] || exit 1
ar rcs "$OBJ/libwineserver.a" $(for n in $BASE; do echo "$OBJ/$n.o"; done)
echo "base archive: $(ar t "$OBJ/libwineserver.a" | wc -l) objects"
