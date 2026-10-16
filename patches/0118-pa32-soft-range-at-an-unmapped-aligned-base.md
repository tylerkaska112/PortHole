# 0118 V8's later 16 GB ask gets a soft range at an unmapped, aligned base (opt-in, with 0105)

`build/ntdll-unix/virtual_ios.c`, only with the 0105 switch.

## Why (RDR2 log of 2026-10-12 01:08, build 0.50.231)
0117 worked: `[pa32] patch0117 1024 MB ask (hint 0x6c6c00000000) served 4GB-aligned inside the idle view at 0x7a00000000` (`[jumbo#19]`), the sandbox ladder and the 16 GB step (`patch0114`) as before.
The next thing V8 does is another 16 GB reserve (`[jumbo#20]`..`#39`: ten random hints that are 16GB-aligned, each again without one), through `NtAllocateVirtualMemoryEx` (no `[jumbo] hinted reserve` lines).
All failed: 0114's hole search needs a 4GB boundary with a free gigabyte after it and there is none left. Then the int3 (`guest_rip 0x73d882205d`), the helper ended, `abort_process` printed `[vmlog]`
(FEX's 16 MB commit churn only), and the restarts died as before.

## What it does
When the hole search fails for a 16/8/4 GB ask in that path, `ios_pa32_soft_far_base()` looks for a base aligned like the hint (4 GB .. 16 GB) between 128 GB and the pool window whose first 512 MB
are unmapped and that no other soft range covers, and records a SOFT range there (nothing reserved). The guest's commits materialise on demand through the existing soft-pool path.
Log: `[pa32] patch0118 N MB reserve (hint ...) served as a soft range at ...`.

## Not verified / open
Whether the Ex path's commits (placeholder replacement) go through the soft-pool materialiser. Whether the range 128 GB..448 GB has unmapped 16GB-aligned prefixes (GPU carveout mappings measured around it). Dead helpers' views still leak.

## Rebuild
`cp -R gl-lib-0117 gl-lib-0118; BASE=.../gl-lib-0117/libntdll_unix.a OUT=.../gl-lib-0118 tools/rebuild_ntdll_object.sh virtual`, then `LIB_OVERRIDES=.../gl-lib-0118 tools/stage_runtime.sh`.
