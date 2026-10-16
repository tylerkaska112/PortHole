# 0086 d2d1.dll, d3d10_1.dll and netprofm.dll added to the ARM64EC farm

Wine's own modules, built unmodified from `vendor/Madeira/wine` with `DEST=$F4_BUILD_ROOT/ec-new build/wine-pe/build-modules.sh d2d1 d3d10_1 netprofm` and staged through `$F4_BUILD_ROOT/ec-out`
(`tools/stage_runtime.sh` copies every DLL there into the arm64ec farm), like patches 0074 and 0078.

Why (Red Dead Redemption 2, 2026-10-08 05:47): Rockstar's `Launcher.exe` delay-loads `d2d1.dll`. The farm had none, the delay-load helper raised `0xC06D007E`, the launcher's crash handler ended it with
`0xFFFF7001`, and PlayRDR2.exe showed "Unable to launch game, please try reinstalling the game." `d2d1.dll` imports `d3d10_1.dll` (also missing; it only forwards into `d3d10core` and `dxgi`, which the farm has),
and the launcher also asked for `netprofm.dll` (network list manager). Still missing and left alone: `Kerberos.dll`, `MSV1_0.dll` (security packages, asked for at startup and not fatal in the log).

sha256: see `docs/OPENGL.sha256`-style record in the commit; d2d1.dll 1,441,792 bytes, d3d10_1.dll 655,360, netprofm.dll 655,360. Unverified on a device: Direct2D drawing goes through Wine's d3d10_1 into DXMT's
d3d10core; if the launcher then fails inside Direct2D rather than at load, that is the next thing to read in the log.
