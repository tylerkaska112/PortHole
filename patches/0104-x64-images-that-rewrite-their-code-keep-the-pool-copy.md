# 0104 Plain x64 images that rewrite their own code keep their pool copy

`build/ntdll-unix/virtual_ios.c`, `ios_x64_image_is_host_data()` (patch 0029's test, which 0102 turned on for launcher sessions). A plain x64 image with a section that is both executable and
writable (`IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_WRITE`) is not given up to "no pool copy": it keeps the pool copy, as before 0029. Log: `[x64-image] 0104 ... has an executable+writable section`.

Why (RDR2 log of 0.50.218, 2026-10-11, `PlayRDR2.exe`): 0102 got the Rockstar chain much further than before (PlayRDR2.exe, Launcher.exe, RockstarErrorHandler.exe, RockstarService.exe, a second
Launcher.exe, SocialClubHelper.exe) with no `JIT pool exhausted`. It then died in a storm: `Unhandled JIT SIGBUS` 16,776 times, `[fault_rip] cnt=233000`, `[redeliv] terminating process`.
Every one is a store into a page of one of these images that the host keeps read-only: `[wr-strip] ... wine_want=5 host_prot=1 (not a strip)`, `Handled self-modifying code`, then the same store
faults again. The pages around the faulting one are `0x2d` (EXEC|WRITECOPY|READ), so the sections are executable and writable by declaration: the packer / anti-tamper unpacks into them.
With no pool copy the emulator's own page protection is all that tracks those writes (the risk 0029 and 0102 both named), and here it did not recover.

libcef.dll (250 MB, the reason for 0102) has no such section, so it still stays out of the pool.

Rebuild: `BASE=$F4_BUILD_ROOT/gl-lib/libntdll_unix.a OUT=$F4_BUILD_ROOT/gl-lib-0104 tools/rebuild_ntdll_object.sh virtual` (after copying `gl-lib` to `gl-lib-0104`), then
`LIB_OVERRIDES=$F4_BUILD_ROOT/gl-lib-0104 tools/stage_runtime.sh`.

Risk: with those images back in the pool, a launcher chain could exhaust it again (0102's problem). It is the small images (Launcher.exe 33 MB, RockstarService.exe) that come back; the big
libcef copies do not. Not verified on a device.
