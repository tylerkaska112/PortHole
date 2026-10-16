# 0113 V8's smallest sandbox (8 GB) is served from the top of the idle real 32 GB view (opt-in, with 0105)

`build/ntdll-unix/virtual_ios.c`, only with the 0105 switch.

## Why (RDR2 log of 2026-10-11 23:41, build 0.50.226)
0112 worked: the 32 GB ask shared the idle view at `0x7800000000` (`[pa32] patch0112 ... shares`), and the helper got past it without corruption. The renderer thread then reserved V8's sandbox the way V8 does: 1.3 TB, 512, 256, 128, 64, 32,
16 and finally 8 GB (its minimum), each with a random hint above the address space ceiling and again without a hint. Every one failed (`[jumbo#6]`..`[jumbo#21]`, `0xc0000017`), the last at 8 GB, and the thread raised
Chrome's out-of-memory exception `0xe0000008`; the unhandled-exception filter ended the process. These asks come through `NtAllocateVirtualMemoryEx` as placeholder reservations (V8 splits them with
`MEM_PRESERVE_PLACEHOLDER` and fills them with `MEM_REPLACE_PLACEHOLDER`); 0112 only covered the plain `NtAllocateVirtualMemory` path. Hints are 4 GB aligned (V8's `kSandboxAlignment`).

## What it does
* Everything bigger than 8 GB keeps failing, so V8 halves down to its minimum.
* The 8 GB ask: the idle 32 GB real view (still uncommitted) is released, its lower 24 GB are reserved again, and the top 8 GB, `[0x7e00000000,0x8000000000)`, become the sandbox's placeholder view.
  Whoever holds the lower view and commits into the top 8 GB gets `STATUS_CONFLICTING_ADDRESSES` rather than shared pages.
* The plain `NtAllocateVirtualMemory` path answers the same ask from the same address inside the existing view (no placeholder).
* Log: `[pa32] patch0113 sandbox placeholder: ...`.

## Not verified / open
V8's heap is then 8 GB in total (4 GB cage + the rest). The 32 GB view's other holder is still unidentified.

## Rebuild
`cp -R gl-lib-0112 gl-lib-0113; BASE=.../gl-lib-0112/libntdll_unix.a OUT=.../gl-lib-0113 tools/rebuild_ntdll_object.sh virtual`, then `LIB_OVERRIDES=.../gl-lib-0113 tools/stage_runtime.sh`.
