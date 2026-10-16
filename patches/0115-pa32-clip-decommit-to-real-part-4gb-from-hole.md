# 0115 Decommit/protect over a hole-backed grant is clipped to its real part; V8's 4 GB asks are served from a hole (opt-in, with 0105)

`build/ntdll-unix/virtual_ios.c`, only with the 0105 switch.

## Why (RDR2 log of 2026-10-11 23:55, build 0.50.228)
* 0114 did what it said: the sandbox ladder (1.3 TB ... 32 GB) failed as before and the 16 GB step was served from a hole (`[pa32] patch0114 16384 MB reserve served from a hole at 0x7300000000`, 1 GB real).
  (No `patch0113` line this time: the 8 GB step was never reached.)
* The next `[vmlog]` lines, printed at the int3 by the 0112 ring, show V8's next move on it: `F tid=037c addr=0x7300000000 size=0x100000000 type=0x4000 (MEM_DECOMMIT) st=0xc000001a`
  (STATUS_UNABLE_TO_FREE_VM): it decommits the first 4 GB of its 16 GB range, which is longer than the 1 GB real view that backs it. V8 then gave that reservation up and asked for 4 GB ten times
  (`[jumbo#19]`..`[jumbo#38]`, hint and null hint alternating, all failing), and took an int3 (`guest_rip 0x73d174402f`).
* The helper restarts (`#39`..`#44`) all died with 0xc0000005 right after their first reserves (leak of the first helper's views: still not released at exit).

## What it does
* `ios_pa32_clip_to_real()`: a MEM_DECOMMIT (NtFreeVirtualMemory) or protect (NtProtectVirtualMemory) whose range starts in a real view and runs on into a soft tail is clipped to the view's end.
* 4 GB reserves that failed elsewhere get the same hole treatment as 16/8 GB, with 2 GB real.

## Not verified / open
V8 may do more with the part beyond the real view (placeholder splits, MEM_REPLACE_PLACEHOLDER commits); those still fail. Dead helpers' views are still not released.

## Rebuild
`cp -R gl-lib-0114 gl-lib-0115; BASE=.../gl-lib-0114/libntdll_unix.a OUT=.../gl-lib-0115 tools/rebuild_ntdll_object.sh virtual`, then `LIB_OVERRIDES=.../gl-lib-0115 tools/stage_runtime.sh`.
