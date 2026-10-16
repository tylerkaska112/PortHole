# 0102 Plain x64 programs stay out of the code pool in a launcher session (turns patch 0029 on there)

`build/ntdll-unix/virtual_ios.c` (`ios_x64_image_data_enabled` no longer caches its answer) and `app/Sources/Core/SessionController.swift` (sets `MADEIRA_X64_IMAGE_DATA=1` when the session runs a launcher with its own service, i.e. `DockInstallers.serverSync`).

Why (RDR2, log of 0.50.178, after the Social Club installer finally worked and the launcher started `SocialClubHelper.exe`): `[jit-pool] EXHAUSTED (image ...+0xefbe000): want=0xefc0000 bump=0x2ff94000/0x40000000` twice, the second for the helper.
Rockstar's launcher and its Social Club helper are Chromium programs; `libcef.dll` is 250 MB and each process takes its own pool copy, in a pool of 1024 MB that already holds Steam's client and the launcher. Nothing runs from those copies: libcef.dll, Launcher.exe (4 x 32 MB),
socialclub.dll, steamclient64.dll (3 x 24 MB), video64.dll... are plain x64 images, which the emulator reads from their own addresses. Patch 0029 (`MADEIRA_X64_IMAGE_DATA=1`, "Big x64 programs in the code pool" in the game's Engine options) already leaves them out;
it was opt-in because it was never verified on a device. It is on now in a launcher session; an `env.MADEIRA_X64_IMAGE_DATA` line of the game still wins. The cached answer in the engine would have kept a stale value for a later launch in the same app run.

Risk: self-modifying code of a packed x64 program (Rockstar's Launcher.exe unpacks itself) is then tracked by the emulator's own page protection only, as for 32-bit images. Log: `[x64-image] 0029 #N ...: is a plain x64 image: no pool copy`. Not verified on a device.
