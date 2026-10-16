# OpenGL (patches/0082, 0083)

Porthole can run Windows games that draw with OpenGL. The work comes from **Connor Gow's fork of Madeira** (<https://github.com/c-gow/Madeira>, test build `opengl-test-7`, commit
`a144444`; the fork's author notes it was written with AI assistance), which adds a WGL driver for Wine on iOS. It was ported onto this tree on branch `opengl-fork`
and is **not device-tested here**.

## How it works
`opengl32.dll` (Wine's) calls its unix side, which sits in `libntdll_unix.a` (`opengl32_unix_call_funcs`, from `wine/dlls/opengl32/unix_{wgl,thunks}.c`) and goes to win32u's
WGL layer. The iOS driver for it is `build/win32u-unix/opengl_ios.c`, with two backends chosen at start (`gl-backend` in madeira.cfg, Settings > Engine options > OpenGL):

* **Desktop OpenGL (Zink).** Mesa's OSMesa renders into an IOSurface; Zink turns OpenGL into Vulkan and MoltenVK turns Vulkan into Metal. OpenGL 3.3 and up; needed by most
  games and by every 32-bit one. Libraries in the app bundle: `gl/libOSMesa.dylib` (Mesa 25.0.7) and `gl/libMoltenVK.dylib` (MoltenVK v1.4.2).
* **OpenGL ES.** Apple's OpenGL ES 3.0 (EAGL, deprecated but still shipped). Fallback when Zink cannot start, or when `gl-backend = gles`.

`Runtime/Winios/WiniosGL.m` presents a finished frame by blitting it to an IOSurface and drawing that on the window's CAMetalLayer (the layer DXMT presents to).
`madeira_frame_count()` adds those presents to DXMT's; the launch screen and the FPS readout use it.

LOVE (LuaJIT) games: `compat/love/lua51.dll` (LuaJIT 2.1, GC64 build) is substituted for the game's own `lua51.dll` when the DLL is mapped (`build/wineserver/luajit_compat.c`);
the game's files are not changed.

## What changed and what did not (read before merging more of the fork)
Applied from the fork: opengl32's unix side; the WGL driver; the x18 store patching, **only for opengl32** (`ios_x18_patch_stores`); wow64 thunks for 32-bit callers;
the wineserver LuaJIT substitution; the short-map fallbacks in `ios_wow_band` (only on devices whose address map is small).

The fork also changed three things for **every** game. Porthole keeps them **off** unless asked, each with an Engine options row (OpenGL group):
* **Thin reservations** (`MADEIRA_THIN_RESERVE=1`): after 8 GB of 1-2 GB read-write reservations, later ones get only a small real head. The fork has it on by default.
* **Audio buffer length** (`env.MADEIRA_AUDIO_IO_MS`): the fork asks iOS for 5 ms I/O passes for every game. Porthole's default is iOS's own length.
* **SDL raw-input joystick off** (`SDL_JOYSTICK_RAWINPUT=0`): not applied; add `env.SDL_JOYSTICK_RAWINPUT = 0` to a game's own lines if an SDL game cannot see the pad.

Turn OpenGL off with `env.MADEIRA_NO_GL = 1` (Engine options > OpenGL > OpenGL: Off): OpenGL calls then fail as they did before.

## Where each file is
* `patches/0082-opengl-engine.patch` — the build/ sources changed or added in `vendor/Madeira` (relative to the tree before this work); `patches/0082-opengl-wine.patch` — the fork's change
  to `wine/dlls/opengl32` (apply with `git -C vendor/Madeira/wine apply --exclude=LICENSE-MADEIRA.md`).
* `patches/0083-opengl-runtime.patch` — changes to `app/Runtime` (applied by `tools/vendor_glue.sh`); `app/Runtime/Winios/WiniosGL.m` is the fork's file.
* `tools/rebuild_gl_objects.sh` — recompiles the objects into copies of `libntdll_unix.a`, `libwin32u_unix.a` and `libwineserver.a`; stage with `LIB_OVERRIDES=<dir> tools/stage_runtime.sh`.
* `tools/stage_runtime.sh` puts `gl/`, `compat/` and the licence texts (from `GL_ASSETS`, default `$F4_BUILD_ROOT/gl-assets`) into the app.

## Binaries taken from the fork's release, not rebuilt here
`gl/libOSMesa.dylib`, `gl/libMoltenVK.dylib`, `compat/love/lua51.dll`, and the PE `opengl32.dll` for arm64ec and i386 (staged over the farm through `ec-out` / `ec-out-i386`).
Their SHA-256 are recorded in `docs/OPENGL.sha256`. The scripts to rebuild them are `vendor/Madeira/build/{mesa-ios,moltenvk-ios,luajit-x64}` (the fork's; they need Mesa 25.0.7,
MoltenVK v1.4.2 and LuaJIT sources); until that is done a rebuild from source cannot reproduce them, and `tools/rebuilt_manifest.sh` does not list them.

## Licences
Mesa (MIT and others), MoltenVK, SPIRV-Cross and SPIRV-Tools (Apache-2.0), cereal (BSD-3), LuaJIT (MIT); texts are bundled in the app's `licenses` folder and the Mesa/MoltenVK patches are
offered under their own licences. The fork's build scripts and driver files are GPL-3.0-or-later with the Madeira Converter Exception (or LGPL-2.1-or-later for the Wine files).
