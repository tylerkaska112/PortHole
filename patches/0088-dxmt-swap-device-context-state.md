# 0088 DXMT: ID3D11DeviceContext1::SwapDeviceContextState no longer aborts

`dxmt/src/d3d11/d3d11_context_impl.cpp` (`SwapDeviceContextState`, new member `swapped_state_`). Applied by `tools/apply_dxmt_patch.sh`.

Why (Red Dead Redemption 2, 2026-10-08, log of 0.50.161): with patch 0087 the Rockstar launcher got as far as creating its Direct3D 11 device and its first window, then
DXMT printed `src\d3d11\d3d11_context_impl.cpp:SwapDeviceContextState is not implemented.` and called `abort()` (`IMPLEMENT_ME`), so Launcher.exe ended with exit code 3 and PlayRDR2.exe showed
"Unable to launch game, please try reinstalling the game." The launcher calls it once after `CreateDeviceContextState`, to put the device in D3D 11.1 mode.

Now the call is accepted: the state passed in becomes the current one and the previous one comes back in `ppPreviousState` (a new object the first time, like a real context's default state).
The pipeline state itself is NOT saved or restored (`MTLD3D11DeviceContextState` holds nothing; the class says "TODO: implement it properly"), so a program that swaps between two live states and expects each to keep its bindings will not get that.

Build: the ARM64EC `d3d11.dll`, release build, same as the one in `app/Madeira/arm64ec-windows` apart from this change (same `.text` size, 0x1e1296):
`meson setup <dir> dxmt --cross-file dxmt/build-arm64ec-win.txt --native-file dxmt/build-osx.txt -Dwine_build_path=<abs>/wine/build-arm64ec -Dbuildtype=release`, `ninja -C <dir> src/d3d11/d3d11.dll`
(PATH needs `toolchains/llvm-mingw-*/bin`, SDKROOT the macOS SDK), then `arm64ec-w64-mingw32-strip` into `$F4_BUILD_ROOT/ec-out/d3d11.dll`, which `tools/stage_runtime.sh` copies over the farm's.
Unverified on a device.
