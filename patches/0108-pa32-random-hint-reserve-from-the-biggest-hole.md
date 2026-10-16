# 0108 A 16 GB reserve at a random hint is served from the map's biggest hole (opt-in, with 0105/0106)

`build/ntdll-unix/virtual_ios.c`: `ios_pa32_soft_back()`, called from the soft-slot fallback of the jumbo reserve path, only with the 0105 switch and only for a 16 GB ask whose hint is not
PartitionAlloc's guard layout (hint offset not 0 and not within 1 MB of 16 GB).

## Why (RDR2 logs of 2026-10-11 22:24, build 0.50.221)
0106 worked: SocialClubHelper.exe ran single-process, got its 32 GB pool at `0x7800000000`, Oilpan's 32 GB from the hold at `0x7000000000`, loaded kernel32/user32/win32u... in that one process. It then
took an int3 in `libcef.dll` at a commit of `0x7400002000` (guest registers hold `0x7400000000` as a base): inside the emulator's band, which the engine keeps `PROT_NONE FEX_ONLY`, so the commit failed
(`0xc0000019`). The reserve that led there was `[jumbo#2]`/`[jumbo#4]`: 16 GB at a RANDOM hint (`0x31b557090000`), answered `[soft-pool] GRANTED soft 0x7800000000 (base returned 0x7557090000)`: a
slot-relative address that sits across the band, the cage holdback and the real pool, with nothing backing it.

## What it does
Finds the largest free hole of the address map (at least 2 GB; in the 22:24 logs the 11 GB hole at `0x7138004000..0x73ffdf0000`), reserves up to 4 GB of it as a REAL view (so commits go through the normal path),
records the rest of the 16 GB as a soft tail, and returns that address; the guest is told it got the full size. Log: `[pa32] patch0108 random-hint 0x... ask: hole ..., N MB real at ...`.

## Not verified / open
If Chromium derives its base by aligning the returned address down to 16 GB (what the registers suggest: `0x7557090000` -> `0x7400000000`), a hole address will give a different, equally wrong base.
Then the right answer is a 16 GB-ALIGNED real range, and the map has none. Look at the next log's commit address and `R14`.

## Rebuild
`BASE=.../gl-lib-0106/libntdll_unix.a OUT=.../gl-lib-0108 tools/rebuild_ntdll_object.sh virtual` (after copying `gl-lib-0106` to `gl-lib-0108`), then `LIB_OVERRIDES=.../gl-lib-0108 tools/stage_runtime.sh`.
