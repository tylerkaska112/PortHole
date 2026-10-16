# Source code and how to rebuild it

Porthole is free software under the GNU General Public License, version 3 or later (`LICENSE`), with an additional permission for the
Apple Metal Shader Converter (`LICENSE-EXCEPTION.md`). You are entitled to the complete source code of the version you have, and to
rebuild and replace the parts that the licences let you replace. This file says where that source is and how it fits together.

## What is where

| Part | Where | Licence |
|---|---|---|
| Porthole (app, library, setup, installers, tunnel, updater, signer) | this repository, `app/`, `Packages/LauncherCore/`, `tools/`. Each release is the tag `v<version>`. | GPL-3.0-or-later |
| Madeira runtime glue (`app/Runtime`) | copied from Madeira (below) with our patches in `patches/` on top | GPL-3.0-or-later (Madeira) |
| Steam sign-in, library, downloads (`app/Sources/Steam`) | this repository; see `docs/STEAM_CLIENT.md` | GPL-3.0-or-later |
| Madeira (Wine, FEX, DXMT, Dock, build scripts) | the git submodule `vendor/Madeira`, pinned to the commit below | GPL-3.0-or-later with its own converter exception; each part keeps its own licence |
| StikJIT 1.5.0 (JIT) | downloaded by `tools/prepare_stikjit.py`, checked against a fixed SHA-256 | MPL-2.0 (idevice MIT, about 130 permissive Rust libraries; see `docs/notices/StikJIT.md`) |

## Pinned upstream commits

| Component | Repository | Commit |
|---|---|---|
| Madeira | https://github.com/willfaust/Madeira | `bbbf8d0e20fd8b75f433f4a8d2a8eaf8d5571120` |
| Wine (LGPL branch) | https://github.com/willfaust/wine | `3a54f56896c85c932870afe6fd91404bbbcb74c8` |
| FEX | https://github.com/willfaust/FEX | `be778d7ba5b98bee0405fd1d6a50d305a0807df0` |
| DXMT | https://github.com/willfaust/dxmt | `8937c08c38f5cb867d995f99b2323739a9f6ffdf` |
| Madeira Dock | https://github.com/willfaust/madeira-dock | `3cadfbea700e4da4b04e331dd7ef1ba633dfacef` |
| StikJIT release | https://github.com/StikDebug/StikJIT/releases/tag/1.5.0 | SHA-256 `444b8d439df8455c34afbb51e279fd225265279195475f9b3fdbcf3a71a27e85` |

Madeira pins the other four itself (`vendor/Madeira/.gitmodules`); the commits above are the ones it records at its commit `bbbf8d0`.
Our changes to those trees are the numbered files in `patches/` (applied by `tools/apply_madeira_patch.sh` and `tools/apply_dxmt_patch.sh`,
and, for the files under `app/Runtime`, by `tools/vendor_glue.sh`).

## Rebuilding

Needs a Mac with Xcode (27) and its Metal toolchain, `xcodegen`, and the build tools Madeira's scripts ask for.

```bash
git clone --recurse-submodules <this repository> && cd <it>
# 1. The native libraries (Wine's unix side, wineserver, DXMT, FEX, FFmpeg, FreeType, GnuTLS), with our patches:
tools/build_wineserver_base.sh                      # the base archive Madeira's wineserver script starts from
tools/build_dxmt_shader_headers.sh && tools/apply_dxmt_patch.sh
tools/apply_madeira_patch.sh
tools/build_fex_ios.sh
#    ...then the build/<name>/build.sh scripts in vendor/Madeira (ntdll-unix, win32u-unix, wineserver, dxmt-ios, ffmpeg, freetype-ios, gnutls-ios)
# 2. Stage them for the Xcode project (also adds our gdiplus.dll, patches/0001):
tools/stage_runtime.sh
# 3. The app:
cp app/Config/Local.xcconfig.example app/Config/Local.xcconfig     # set your own bundle id
cd app && xcodegen generate
xcodebuild -project Porthole.xcodeproj -scheme Porthole -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Wine, GnuTLS, FFmpeg and other LGPL parts are linked statically. Because the steps above rebuild them, you can change any of them and
produce a working app with your modified version, then sign it yourself (Porthole can do that on the device).

Microsoft's Visual C++ runtime is not part of this source or of the app: the app downloads it from Microsoft (Settings > Advanced > Windows components),
so a build needs no copy of it. (A private test build can still bundle a local copy: put the DLLs in `VCRUNTIME_DIR` and package with `F4_BUNDLE_VCRUNTIME=1`.)
Apple's Metal Shader Converter comes from Apple under its own agreement (`d3d12/` in the app).

**Honest status:** this sequence is assembled from the scripts we use. A rebuild from scratch on a clean machine, following only this
file, has not been done yet; if a step is missing or wrong, that is a bug in this document and we want to hear about it.
