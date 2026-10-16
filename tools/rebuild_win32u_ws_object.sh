#!/bin/bash
# Recompile single objects of libwin32u_unix.a and libwineserver.a from vendor/Madeira/build into COPIES (the libraries in vendor/ are not touched).
# Same flags as tools/rebuild_gl_objects.sh (which has the longer story). Used by patches 0119 (PR 222, 248).
#   BASE=<dir holding libwin32u_unix.a and libwineserver.a> OUT=<dir> tools/rebuild_win32u_ws_object.sh win32u:driver_ios:driver wineserver:fd_ios:fd_ios
#   each argument is  <library>:<source name without .c>:<archive member name without .o>
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$HERE/tools/local.env" ] && . "$HERE/tools/local.env"
F4_BUILD_ROOT="${F4_BUILD_ROOT:-$HERE/build}"
M="$HERE/vendor/Madeira"; BUILD="$M/build"; WINE_SRC="$M/wine"; WINE_BUILD="$WINE_SRC/build-macos"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
OUT="${OUT:?OUT=<dir>}"; BASE="${BASE:?BASE=<dir with libwin32u_unix.a and libwineserver.a>}"; WORK="$OUT/obj"; mkdir -p "$WORK"
[ "$BASE" = "$OUT" ] || { cp "$BASE/libwin32u_unix.a" "$OUT/libwin32u_unix.a"; cp "$BASE/libwineserver.a" "$OUT/libwineserver.a"; }
OBJCOPY=$(command -v llvm-objcopy || echo /opt/homebrew/opt/llvm/bin/llvm-objcopy)
[ -x "$OBJCOPY" ] || OBJCOPY=$(ls /opt/homebrew/Cellar/llvm/*/bin/llvm-objcopy | tail -1)
RENAME=(); for s in alloc_user_handle free_user_handle get_virtual_screen_rect destroy_thread_windows get_window_thread is_desktop_class is_message_class is_window_visible mirror_region send_notify_message shared_session user_shared_data; do RENAME+=(--redefine-sym "_${s}=_ws_${s}"); done
for spec in "$@"; do
  lib=${spec%%:*}; rest=${spec#*:}; src=${rest%%:*}; name=${rest##*:}
  case "$lib" in
    win32u)
      xcrun -sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 \
        -O2 -fPIC -fvisibility=hidden -fno-stack-protector -fno-strict-aliasing \
        -Wno-implicit-function-declaration -Wno-int-conversion \
        -include "$BUILD/win32u-unix/config_ios.h" -include "$BUILD/ntdll-unix/shims/wine_ios_exit.h" \
        -I"$BUILD/win32u-unix" -I"$WINE_BUILD/include" -I"$BUILD/ntdll-unix/shims" \
        -I"$WINE_BUILD/dlls/win32u" -I"$WINE_SRC/dlls/win32u" -I"$WINE_BUILD/include" -I"$WINE_SRC/include" \
        -D__WINESRC__ -D_WIN32U_ -D_ACRTIMP= -DWINBASEAPI= -DSYSTEMDLLPATH=\"\" -DWINE_UNIX_LIB -DWINE_IOS=1 \
        -D__wine_unix_lib_init=win32u_unix_lib_init \
        -USONAME_LIBFREETYPE -USONAME_LIBFONTCONFIG -USONAME_LIBEGL -USONAME_LIBVULKAN -USONAME_LIBGNUTLS -UHAVE_FT2BUILD_H \
        -c "$BUILD/win32u-unix/$src.c" -o "$WORK/$name.o" 2>"$WORK/$name.err" || { grep error "$WORK/$name.err" | head; exit 1; }
      xcrun -sdk iphoneos ar d "$OUT/libwin32u_unix.a" "$name.o" 2>/dev/null || true
      ( cd "$WORK" && xcrun -sdk iphoneos ar r "$OUT/libwin32u_unix.a" "$name.o" 2>&1 | grep -v "^ar: creating" || true ) ;;
    wineserver)
      xcrun -sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 -O2 \
        -I"$WINE_SRC/include" -I"$WINE_SRC/include/wine" -I"$WINE_SRC/build-macos/include" -I"$BUILD/wineserver" -I"$WINE_SRC/server" \
        -I"$BUILD/ntdll-unix/shims" -I"$BUILD/madsync" -DHAVE_LINUX_NTSYNC_H=1 \
        -include "$BUILD/wineserver/config_ios.h" -include stdarg.h -include "$BUILD/wineserver/unicode_fix.h" -include "$BUILD/wineserver/wineserver_ios_kill.h" \
        -DBINDIR=\"/usr/local/bin\" -DDATADIR=\"/usr/local/share\" -D__WINESRC__ -DWINE_IOS=1 -Dmain=wineserver_main -Wno-implicit-function-declaration \
        -c "$BUILD/wineserver/$src.c" -o "$WORK/ws_$name.o" 2>"$WORK/ws_$name.err" || { grep error "$WORK/ws_$name.err" | head; exit 1; }
      cp "$WORK/ws_$name.o" "$WORK/$name.o"
      "$OBJCOPY" "${RENAME[@]}" "$WORK/$name.o"
      xcrun -sdk iphoneos ar d "$OUT/libwineserver.a" "$name.o" 2>/dev/null || true
      ( cd "$WORK" && xcrun -sdk iphoneos ar r "$OUT/libwineserver.a" "$name.o" 2>&1 | grep -v "^ar: creating" || true ) ;;
    *) echo "library: win32u or wineserver"; exit 1 ;;
  esac
done
xcrun -sdk iphoneos ranlib "$OUT/libwin32u_unix.a"; xcrun -sdk iphoneos ranlib "$OUT/libwineserver.a"
echo "wrote $OUT: win32u $(ar t "$OUT/libwin32u_unix.a" | wc -l | tr -d ' '), wineserver $(ar t "$OUT/libwineserver.a" | wc -l | tr -d ' ') members"
