# 0117 V8's 1 GB / 4 GB 4GB-aligned asks are served from fixed slots inside the 32 GB real view (opt-in, with 0105)

`build/ntdll-unix/virtual_ios.c`, only with the 0105 switch.

## Why (RDR2 log of 2026-10-12 00:57, build 0.50.230)
0116 did not fire: no `[pa32] patch0116` line. The sandbox ladder, the 16 GB step (`patch0114`, 1 GB real at `0x7300000000`) and the three 1 GB asks went exactly as in 0.50.229
(`[jumbo#19]`..`#21` came back `0x721fa80000`, `0x721fec0000`, `0x721faa0000`: 64 KB aligned; the 5119 MB over-reserve failed; second consumer `#24`..`#28` the same; Chrome OOM 0xe0000008;
`[vmlog]` at abort now printed but showed only FEX's 16 MB commit churn). The map has no 4GB boundary with a free gigabyte after it: the furniture window's allocations and 0114's real part sit on all of them.

## What it does
For a 1 GB or 4 GB ask whose hint is 4GB-aligned, after the usual candidates failed: fixed 4GB-aligned slots `0x7a00000000, 0x7b00000000, 0x7e00000000, 0x7f00000000`, inside the existing 32 GB real view
(its holder, PartitionAlloc's regular and BRP halves at `0x7800000000`/`0x7c00000000`, only uses the first MB of each half). No new view is created, so a guest MEM_RELEASE at the slot gets
STATUS_FREE_VM_NOT_AT_BASE rather than unmapping the holder's view. 0116's hole attempt stays as the fallback. Log: `[pa32] patch0117 N MB ask (hint ...) served 4GB-aligned inside the idle view at ...`.

## Not verified / open
Four slots only; if V8 asks for more, or releases and re-asks, they run out (taken flags are never given back). Dead helpers' views still leak.

## Rebuild
`cp -R gl-lib-0116 gl-lib-0117; BASE=.../gl-lib-0116/libntdll_unix.a OUT=.../gl-lib-0117 tools/rebuild_ntdll_object.sh virtual`, then `LIB_OVERRIDES=.../gl-lib-0117 tools/stage_runtime.sh`.
