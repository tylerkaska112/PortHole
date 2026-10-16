# 0106 Rockstar's Chromium host runs single-process; the Oilpan ask is not given a soft slot (opt-in, with 0105)

`build/ntdll-unix/process_ios.c`, `virtual_ios.c`. Both only with patch 0105's switch (`MADEIRA_PA_POOL32_SOFT=1` / `pa-pool32-soft = 1`); the app sets it, and `MADEIRA_ROCKSTAR_SINGLE_PROCESS=1`, for Red Dead Redemption 2 (GameFixes).

## Why (RDR2 log of 2026-10-11 22:14, build 0.50.220)
0105 worked as intended: `[pa32] ... the emulator's band is [0x7400000000,0x7600000000)` and the first Chromium host (`SocialClubHelper.exe`, no `--type=`) got `[jumbo#1] 32 GB -> 0x7800000000`, a real aligned pool.
It then died in `libcef.dll`'s init (`status 80000003`) because of the third reserve, Oilpan's caged heap (32 GB aligned to 32 GB):
* the 4 GB hold at `0x7000000000` failed (`kr=3`): the JIT pool's RW alias sits there (StikJITHelper remaps it at exactly `0x7000000000`; 0018's own change to move it was not in the patch file);
* the soft-slot fallback of the jumbo path then handed out `0x7c00000000` (soft, 16 GB-aligned only, and inside the real `[0x7800000000,+32GB)` view); Chromium saw it was not aligned, released it,
  and `ml1285 free-refused ... status=0xc000009f ... view=0x7800000000+0x800000000` made that release fail, so PartitionAlloc's check took an int3.

## Changes
* **0107** (`app/Runtime/StikJITHelper.swift`, applied by `tools/vendor_glue.sh`): with the switch on the RW alias starts at `0x7100000000`, above Oilpan's 4 GB.
* **virtual_ios.c**: while Oilpan's 4 GB hold is live, an exact 32 GB reserve is not given a soft slot; it falls through to `ios_pa32_cage_grant`, which serves it from the hold.
* **process_ios.c**: `SocialClubHelper.exe` without `--type=` gets ` --single-process --disable-gpu --disable-gpu-compositing --enable-logging=file` appended (once; the command line is logged), and any
  `SocialClubHelper.exe --type=...` is refused (`STATUS_ACCESS_DENIED`). Same idea as steamwebhelper's and as 0030 for Ubisoft: every Wine process shares ONE host address space, so a second Chromium
  process cannot get its own 32 GB pool.

## Risks / not verified
Ubisoft's CEF ignored these switches in 0.50.66 and ended itself with `GPU process isn't usable` when its helpers were refused; Rockstar's may too. If so the log shows the refusal line and then
Chromium ending. Not verified on a device.

## Rebuild
`BASE=.../gl-lib-0105/libntdll_unix.a OUT=.../gl-lib-0106 tools/rebuild_ntdll_object.sh virtual process` (after copying `gl-lib-0105` to `gl-lib-0106`), then `LIB_OVERRIDES=.../gl-lib-0106 tools/stage_runtime.sh`.
