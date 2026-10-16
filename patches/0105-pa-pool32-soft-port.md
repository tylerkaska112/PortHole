# 0105 A 32 GB-aligned pool for Chromium's allocator (port of 0018, opt-in)

`build/ntdll-unix/virtual_ios.c`, `signal_arm64_ios.c`. The experiment of `patches/0018-pa-pool32-soft.*` (branch `electron-va-experiment`, 5 October) ported onto the current engine; the original
no longer applies (the engine moved: Madeira update of 7 October, patches 0073-0102). Same design, same switch: `pa-pool32-soft = 1` in a game's `madeira.cfg` lines, or `MADEIRA_PA_POOL32_SOFT=1`
in the environment. Off unless set, and then nothing changes. Porthole sets it for Red Dead Redemption 2 (`GameFixes`, Steam app 1174180).

## Why (RDR2 log of 2026-10-11, 22:03)
Rockstar's launcher showed "timed out loading both its online and offline content". Its Chromium helper (`SocialClubHelper.exe`) was started 9 times and every copy stopped in `chrome_elf.dll` at start
(`Initializing dlls ... failed, status 80000003`). The log has `[jumbo#N]`: three 32 GB reserves that all landed at `0x7400000000` (16 GB-aligned only; PartitionAlloc frees them and retries), then
`size=0xfffff0000` (64 GB - 64 KB, its fall-back to align the pool itself) failing with `0xc0000017`. The only 32 GB-aligned slot that could work is `[0x7800000000,0x8000000000)`, and the emulator's
band is the top 16 GB of it. Same wall as the Electron game of 5 October (`patches/0018-pa-pool32-soft.md`).

## What it does (with the switch on)
* The emulator's band moves from `[0x7c00000000,0x8000000000)` to an 8 GB band at `0x7400000000`, only if that range is free at start-up. The ordinary slot walk then hands the guest the real,
  aligned `[0x7800000000,0x8000000000)`.
* V8's 8 GB cage holdback moves to `0x7600000000`; the first 4 GB of `0x7000000000` is held for Oilpan's caged heap; the JIT pool alias sits above it; steered reserves follow the band and may not enter the pool;
  V8's last-resort sandbox ask is served from the holdback; the wide address-space claim stays on. Log lines: `[pa32] patch0018 ...`.
* New against 0018: the Dock steering preference of patch 0077 (steered reserves into `[0x7400000000,0x7c00000000)`) is skipped, since that range now holds the pool.

Port notes: 20 + 5 hunks; two (swap eligibility, the first steered allocation) were redone by hand because the surrounding code had changed.

## Not verified on a device
Whether Chromium gets past the allocator with this layout in RDR2's launcher chain, and what fails next (V8's sandbox, Oilpan, the CoreAnimation range guard are the known candidates from the Electron work).
Look for `[pa32] patch0018 the emulator's band is [0x7400000000,...)` and then the `[jumbo#N]` lines: the third 32 GB ask should return `0x7800000000`.

## Rebuild
`BASE=$F4_BUILD_ROOT/gl-lib-0104/libntdll_unix.a OUT=$F4_BUILD_ROOT/gl-lib-0105 tools/rebuild_ntdll_object.sh virtual signal_arm64` (after copying `gl-lib-0104` to `gl-lib-0105`), then
`LIB_OVERRIDES=$F4_BUILD_ROOT/gl-lib-0105 tools/stage_runtime.sh`.
