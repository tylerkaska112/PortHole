# 0109 With the 0105 switch the emulator's band is 16 GB again and there is no 8 GB cage holdback; random-hint reserves keep 1 GB real

`build/ntdll-unix/virtual_ios.c`, only with the 0105 switch (`MADEIRA_PA_POOL32_SOFT=1` / `pa-pool32-soft = 1`).

## Why (RDR2 log of 2026-10-11 22:34, build 0.50.222)
0108 worked as written: the two 16 GB random-hint reserves got real starts in the biggest holes (`[pa32] patch0108 ... 4096 MB real at 0x718e570000`, `... 0x728e780000`) and there was no more int3 and no
`status 80000003`. The run then ran out of address space instead:
* the emulator's band (8 GB since 0105) was exhausted already at boot of the Steam client (`[cage] holdback handed to the allocator: the band is exhausted` at line 4414, long before Rockstar's chain);
  at the end `[va-scan] FAILED window=0x7400000000..0x7600000000 ... maxgap=0x10000`, `arm64ec_thread_init failed c0000017`, `[alloc-fail] FEXAlloc could not allocate` and an AV writing through the
  null OpDispatcher pointer of the thread that could not be set up. 116 threads, ~31 MB of emulator memory each (`FEXMem_CallRetStacks` 16 MB, `OpDispatcher` 16 MB, `Frontend` 8 MB, ...);
* the furniture window went from 11 GB free to 0.8 GB free, partly because 0108 took 2 x 4 GB of it for the real parts.

## Changes
* the band is 16 GB, `[0x7400000000,0x7800000000)` (0018's try 3 layout), still leaving `[0x7800000000,0x8000000000)` for the 32 GB pool;
* no 8 GB V8 cage holdback with the switch (it sat at `0x7600000000`, in the way of the bigger band; Oilpan has its own slot, and nothing asked for an 8 GB cage in these logs);
* the real part of a random-hint 16 GB ask is 1 GB, not 4 GB.

## Not verified
`[fex-arena] ml793 PUBLISHED [0x7400000000,0x7800000000)` and `[cage] 0109 no 8GB holdback` are the lines to look for. The furniture window (`[window] 0x7048000000..0x7400000000`) is the next place to run out.

## Rebuild
`BASE=.../gl-lib-0108/libntdll_unix.a OUT=.../gl-lib-0109 tools/rebuild_ntdll_object.sh virtual` (after copying `gl-lib-0108` to `gl-lib-0109`), then `LIB_OVERRIDES=.../gl-lib-0109 tools/stage_runtime.sh`.
