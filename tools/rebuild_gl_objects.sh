#!/bin/bash
# Recompile the objects of the OpenGL work (patches/0082) into COPIES of the engine's static libraries; the libraries in vendor/ are not touched.
# Same flags as build/ntdll-unix/build.sh (compile_unixlib), build/win32u-unix/build.sh (compile_one) and build/wineserver/build.sh, so the result matches a full build
# without running those scripts (they rebuild everything and have traps of their own; see docs/OPENGL.md).
#   OUT=<dir> tools/rebuild_gl_objects.sh          default OUT=$F4_BUILD_ROOT/gl-lib
# Writes OUT/libntdll_unix.a (opengl32 unix side + the objects tools/rebuild_ntdll_object.sh already replaced, taken from OUT's own copy if present),
# OUT/libwin32u_unix.a (driver.o with the GL hook, opengl_ios.o) and OUT/libwineserver.a (mapping.o, luajit_compat.o).
# Stage them with LIB_OVERRIDES=$OUT tools/stage_runtime.sh
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$HERE/tools/local.env" ] && . "$HERE/tools/local.env"
F4_BUILD_ROOT="${F4_BUILD_ROOT:-$HERE/build}"
M="$HERE/vendor/Madeira"; BUILD="$M/build"; WINE_SRC="$M/wine"; WINE_BUILD="$WINE_SRC/build-macos"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
OUT="${OUT:-$F4_BUILD_ROOT/gl-lib}"; WORK="$OUT/obj"; mkdir -p "$WORK"
NTDLL_BASE="${NTDLL_BASE:-$F4_BUILD_ROOT/ntdll-lib-gl/libntdll_unix.a}"
[ -f "$NTDLL_BASE" ] || NTDLL_BASE="$M/app/Madeira/libntdll_unix.a"
cp "$NTDLL_BASE" "$OUT/libntdll_unix.a"
cp "$M/app/Madeira/libwin32u_unix.a" "$OUT/libwin32u_unix.a"
cp "$M/app/Madeira/libwineserver.a" "$OUT/libwineserver.a"

# 1. opengl32's unix side -> libntdll_unix.a (the tables are renamed per library, as compile_unixlib does)
for pair in "unix_wgl:opengl32_wgl" "unix_thunks:opengl32_thunks"; do
  src=${pair%%:*}; name=${pair##*:}
  xcrun -sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 \
    -O2 -fPIC -fvisibility=hidden -fno-stack-protector -fno-strict-aliasing \
    -Wno-implicit-function-declaration -Wno-int-conversion \
    -include "$WINE_BUILD/include/config.h" -include "$BUILD/ntdll-unix/shims/wine_ios_exit.h" \
    -I"$BUILD/ntdll-unix/shims" -I"$BUILD/madsync" -DHAVE_LINUX_NTSYNC_H=1 \
    -I"$WINE_BUILD/include" -I"$WINE_SRC/include" \
    -D__WINESRC__ -D_NTSYSTEM_ -D_ACRTIMP= -DWINBASEAPI= -DWINE_UNIX_LIB -DWINE_IOS=1 \
    -D__wine_unix_call_funcs=opengl32_unix_call_funcs -D__wine_unix_call_wow64_funcs=opengl32_unix_call_wow64_funcs \
    -I"$WINE_SRC/dlls/opengl32" \
    -c "$WINE_SRC/dlls/opengl32/$src.c" -o "$WORK/$name.o" 2>"$WORK/$name.err" || { grep error "$WORK/$name.err" | head; exit 1; }
  xcrun -sdk iphoneos ar d "$OUT/libntdll_unix.a" "$name.o" 2>/dev/null || true
  ( cd "$WORK" && xcrun -sdk iphoneos ar r "$OUT/libntdll_unix.a" "$name.o" 2>&1 | grep -v "^ar: creating" || true )
done
xcrun -sdk iphoneos ranlib "$OUT/libntdll_unix.a"

# 2. win32u's iOS driver hook and the WGL driver
FREETYPE_DIR="$BUILD/freetype-ios"
for pair in "driver_ios:driver" "opengl_ios:opengl_ios"; do
  src=${pair%%:*}; name=${pair##*:}
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
  ( cd "$WORK" && xcrun -sdk iphoneos ar r "$OUT/libwin32u_unix.a" "$name.o" 2>&1 | grep -v "^ar: creating" || true )
done
xcrun -sdk iphoneos ranlib "$OUT/libwin32u_unix.a"

# 3. wineserver: the LuaJIT substitution at map time. Symbol renames are the ones build/wineserver/build.sh applies to every object of the archive.
OBJCOPY=$(command -v llvm-objcopy || echo /opt/homebrew/opt/llvm/bin/llvm-objcopy)
[ -x "$OBJCOPY" ] || OBJCOPY=$(ls /opt/homebrew/Cellar/llvm/*/bin/llvm-objcopy | tail -1)
RENAME=(); for s in alloc_user_handle free_user_handle get_virtual_screen_rect destroy_thread_windows get_window_thread is_desktop_class is_message_class is_window_visible mirror_region send_notify_message shared_session user_shared_data; do RENAME+=(--redefine-sym "_${s}=_ws_${s}"); done
for pair in "mapping_ios:mapping" "luajit_compat:luajit_compat"; do
  src=${pair%%:*}; name=${pair##*:}
  xcrun -sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 -O2 \
    -I"$WINE_SRC/include" -I"$WINE_SRC/include/wine" -I"$WINE_SRC/build-macos/include" -I"$BUILD/wineserver" -I"$WINE_SRC/server" \
    -I"$BUILD/ntdll-unix/shims" -I"$BUILD/madsync" -DHAVE_LINUX_NTSYNC_H=1 \
    -include "$BUILD/wineserver/config_ios.h" -include stdarg.h -include "$BUILD/wineserver/unicode_fix.h" -include "$BUILD/wineserver/wineserver_ios_kill.h" \
    -DBINDIR=\"/usr/local/bin\" -DDATADIR=\"/usr/local/share\" -D__WINESRC__ -DWINE_IOS=1 -Dmain=wineserver_main -Wno-implicit-function-declaration \
    -c "$BUILD/wineserver/$src.c" -o "$WORK/ws_$name.o" 2>"$WORK/ws_$name.err" || { grep error "$WORK/ws_$name.err" | head; exit 1; }
  cp "$WORK/ws_$name.o" "$WORK/$name.o"
  "$OBJCOPY" "${RENAME[@]}" "$WORK/$name.o"
  xcrun -sdk iphoneos ar d "$OUT/libwineserver.a" "$name.o" 2>/dev/null || true
  ( cd "$WORK" && xcrun -sdk iphoneos ar r "$OUT/libwineserver.a" "$name.o" 2>&1 | grep -v "^ar: creating" || true )
done
xcrun -sdk iphoneos ranlib "$OUT/libwineserver.a"
echo "wrote $OUT: ntdll $(ar t "$OUT/libntdll_unix.a" | wc -l | tr -d ' '), win32u $(ar t "$OUT/libwin32u_unix.a" | wc -l | tr -d ' '), wineserver $(ar t "$OUT/libwineserver.a" | wc -l | tr -d ' ') members"
