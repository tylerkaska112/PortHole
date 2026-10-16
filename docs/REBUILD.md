# Rebuilding what Porthole ships

Porthole is the app in `app/` around the Madeira runtime (`vendor/Madeira`, a submodule pinned in `.gitmodules`/the gitlink). Most of what runs is Madeira's own binaries, byte for byte.
This page lists what is **not**: every binary that differs from the pinned snapshot, the patch behind it, and how to rebuild it. `docs/REBUILT_BINARIES.sha256` has the SHA-256 of each,
and `tools/rebuilt_manifest.sh --check` compares your copy against it (a rebuild that is not byte-identical is normal for DLLs and archives; then regenerate the list on purpose, and see `docs/ENGINE.md` for the engine bump).

## What differs from the pinned snapshot

| Binary | Why | Patch / how |
|---|---|---|
| `arm64ec-windows/gdiplus.dll` (also `patches/0001-gdiplus.dll`) | the snapshot ships none and some games will not start without it | `patches/0001-gdiplus.md` |
| `arm64ec-windows/d3d11.dll` | DXMT fixes (precise math, 3D copy) | `patches/0004`, `0005`; `tools/apply_dxmt_patch.sh`, `build/dxmt-ios` |
| `arm64ec-windows/xinput1_1..4.dll`, `i386-windows/xinput1_1..4.dll` | controller rumble | `patches/0017-xinput-vibration.md` (has the exact rebuild steps) |
| `arm64ec-windows/xtajit64.dll` | FEX guard for a context that is gone at exit | `patches/0015-xtajit64-context-guard.py`, applied to a copy of the earlier file (a rebuild from the tree does not reproduce the shipped file; `0015-...md` says why) |
| `aarch64-windows/wow64.dll` | prints the text of a 32-bit program's hard error (diagnostic) | `patches/0024-wow64-hard-error-text.md` |
| `aarch64-windows/wow64win.dll` | window class atom fix | `patches/0009`, `build/wine-pe` |
| `arm64ec-windows/{fwpuclnt,rstrtmgr,srvcli,tdh,virtdisk,webservices}.dll` | extra Wine modules some launchers and games load | built from the pinned Wine tree with `bash build/wine-pe/build-modules.sh <names>` |
| `i386-windows/{ntdll,kernel32,kernelbase}.dll` | Windows' `8b ff` hot-patch prologue instead of `66 90` (experiment, for a launcher whose hooks fail) | `patches/0025-i386-hotpatch-prologue.md`; output goes to `$F4_BUILD_ROOT/ec-out-i386` |
| `arm64ec-windows/kernelbase.dll` | `SetThreadIdealProcessorEx` reports success (Counter-Strike 2's Embree crash) | `patches/0038-ideal-processor-ex.md`; `build/wine-pe/build-modules.sh kernelbase` |
| `libntdll_unix.a` (not tracked) | thread registry reuse, SIMD store forms | `patches/0012`, `0013`: compile `signal_arm64_ios.c`, `ar r` it into the archive |
| `libwin32u_unix.a` (not tracked) | display/message changes (0009), gamepad vibration (0017) | `bash build/win32u-unix/build.sh`, then remove duplicate members (see below) |

App-side sources of the runtime (`app/Runtime`) are copied from the pinned snapshot by `tools/vendor_glue.sh` and then patched with `patches/0011` and `0016`.

## Where the results go

`tools/stage_runtime.sh` builds the runtime the app project links:

* the pinned snapshot's libraries and farms are linked or copied;
* every `*.dll` in `$F4_BUILD_ROOT/ec-out` is copied over the arm64ec farm, every `*.dll` in `$F4_BUILD_ROOT/ec-out-i386` over the 32-bit farm;
* `gdiplus.dll` from `patches/` is added if none is there; Microsoft's VC runtime is **not** included (the app downloads it, see `docs/COMPLIANCE.md`).

`F4_BUILD_ROOT` is set in the untracked `tools/local.env`; its default is `build/` in the repository.

## Known traps

* `build/win32u-unix/build.sh` merges FreeType into `libwin32u_unix.a` again on every run. Afterwards extract the archive, `ar rcs` the unique member names and `ranlib`: it must have **89** members (131 or 173 means duplicates).
* The arm64ec and i386 farms use the same file names for the xinput DLLs; keep the two build outputs in separate folders (`ec-out`, `ec-out-i386`).
* `xtajit64.dll` is a patched binary: always start from the file recorded in `0015-...md`, never from a fresh FEX build.

## Checking a rebuild

1. `tools/rebuilt_manifest.sh --check` (reports which of the listed binaries differ).
2. If you changed how games run on purpose, `tools/engine.sh bump` (otherwise the compatibility badges keep counting reports from the old engine).
3. `tools/stage_runtime.sh`, build the app (`docs/INSTALL.md`), and run a game you know (Factorio is the usual one).

## Relinking with a different library (LGPL)

Wine, GnuTLS and FFmpeg are statically linked from the archives in `RuntimeStage/lib` (`libntdll_unix.a`, `libwin32u_unix.a`, `libgnutls.a`, `libavcodec.a`, ...). To use your own build of one, put your
archive in a folder next to copies or links of the others and point the link at it, then package and sign as usual:

```bash
xcodebuild -project app/Porthole.xcodeproj -scheme Porthole -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/DD CODE_SIGNING_ALLOWED=NO LIBRARY_SEARCH_PATHS="/path/to/your/lib"
tools/package_app.sh build/DD/Build/Products/Release-iphoneos/Porthole.app Porthole-relinked.ipa      # unsigned; sign it with your own certificate
```

Tried on 2026-10-05 on the maintainer's machine: `libgnutls.a` replaced by a repacked copy (`libtool -static`), the app relinked without errors and produced a different executable. Not yet tried:
on a machine that has never built Porthole, from a fresh clone, or run on a device after relinking.

## Not yet tested

A relink from a fresh clone on a clean machine (the section above was done where every tool and the runtime stage already existed); see `docs/COMPLIANCE.md`.
