# 0116 V8's 1 GB (and 4 GB) asks get a real 4GB-aligned range; `[vmlog]` also prints at abort_process (opt-in, with 0105)

`build/ntdll-unix/virtual_ios.c`, `thread_ios.c`; only with the 0105 switch (the `[vmlog]` line prints for any process that aborts with a non-zero status).

## Why (RDR2 log of 2026-10-12 00:00, build 0.50.229)
* 0115 worked: the 16 GB step was served (`patch0114`), V8's 4 GB decommit no longer failed, and V8 went on to its next reserves.
* Those are 1 GB asks with 4GB-aligned hints (`[jumbo#19]`..`#21`): three exact tries, each answered with an address that is only 64 KB aligned (`0x723e390000`, the kernel's pick after the
  4GB-aligned candidates `0x7200000000`/`0x7300000000`... failed: `0x7300000000` is where 0114 had just put the 16 GB range's real part), then the over-reserve `[jumbo#22]` (5119 MB = 1 GB + 4 GB - 64 KB) found no gap.
  A second 1 GB consumer did the same (`#24`..`#28`). Chrome raised its out-of-memory exception 0xe0000008 and the helper ended. In 0.50.227's run the third try had landed on a free `0x7300000000` by luck.
* The legacy "4 GB cage soft grant" at `0x7600000000`/`0x7500000000` sits inside the emulator's band with the 0105 layout.

## What it does
* 1 GB and 4 GB asks with a 4GB-aligned hint, once the usual candidates failed: `ios_pa32_soft_back2(size, align 4 GB, cap = size or 2 GB)` puts them 4GB-aligned in the biggest hole (4 GB asks keep a 2 GB real part and a soft tail).
  Log: `[pa32] patch0116 N MB ask (hint ...) served 4GB-aligned at ...`.
* The legacy 4 GB soft cages are skipped when the switch is on.
* `[vmlog]` is also printed by `abort_process` (status != 0), because Chrome's out-of-memory exception does not go through the int3 dump.

## Not verified / open
Whether two or three 1 GB aligned ranges fit the biggest holes (the furniture window had ~6.4 GB free); the soft tails of earlier grants overlap whichever hole is picked. Dead helpers still leak.

## Rebuild
`cp -R gl-lib-0115 gl-lib-0116; BASE=.../gl-lib-0115/libntdll_unix.a OUT=.../gl-lib-0116 tools/rebuild_ntdll_object.sh virtual thread`, then `LIB_OVERRIDES=.../gl-lib-0116 tools/stage_runtime.sh`.
