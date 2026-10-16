# 0089 Direct2D: an ID2D1DCRenderTarget works on a device without IDXGISurface1 (DXMT) + more pool for launchers

`wine/dlls/d2d1/dc_render_target.c`, `d2d1_private.h` (new field `target_resource`, new `d2d_dc_render_target_present_readback`). Built with `DEST=$F4_BUILD_ROOT/ec-new bash build/wine-pe/build-modules.sh d2d1`, copied to `$F4_BUILD_ROOT/ec-out/d2d1.dll`.

Why (RDR2, log of 0.50.163): Rockstar's launcher draws its window through an `ID2D1DCRenderTarget`. Wine's d2d1 does that with `IDXGISurface1::GetDC` on the render target's texture; DXMT's textures have
no `IDXGISurface1`, `BindDC` ignored the failed `QueryInterface`, and `EndDraw` -> `Present` called through a NULL pointer: `c0000005` at `d2d_dc_render_target_present` (d2d1 rva 0x1f620), either swallowed by a window
procedure (the launcher kept running, drawing nothing) or killing the launcher outright.

Now `BindDC` keeps the bitmap's texture, and when there is no `IDXGISurface1` the present copies the texture to a staging texture, maps it and puts the pixels on the target DC with `SetDIBitsToDevice` (B8G8R8A8 / B8G8R8X8 only; anything
else logs a fixme and draws nothing). The device context is not read back at `BeginDraw` (what was on the DC is not copied into the texture first), so a program that draws only part of its window each time would repaint on a cleared texture.

Also (app, not a patch): a Dock start that needs the service step (`DockInstallers.serverSync`) gets a 1152 MB JIT pool instead of 896 MB when madeira.cfg has no `pool` line. In the same log the pool ran dry
(`[jit-pool] EXHAUSTED` at 683 MB used + 244 MB reserved) with the Steam client, the launcher and its restarted copy alive: every process holds its own copy of every library it loads.

Not verified on a device. Seen in the same log and NOT addressed: ~400,000 write faults on code pages in 112 s (thread 013c of Launcher.exe; Chromium's JIT writing code), which makes the launcher's start take about two minutes.
