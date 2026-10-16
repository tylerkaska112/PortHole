# 0112 The V8 sandbox's 32 GB ask shares the idle real 32 GB view; a ring of virtual-memory calls is dumped at a guest int3 (opt-in, with 0105)

`build/ntdll-unix/virtual_ios.c`, `signal_arm64_ios.c`; only with the 0105 switch (`MADEIRA_PA_POOL32_SOFT=1`).

## What the 0.50.225 log (23:24) showed
* The pools in the Rockstar helper (`SocialClubHelper.exe`, process `peb 0x115ccc000`): `[jumbo#1]` 32 GB real at `0x7800000000` (never committed: 0 MB in 41 calls for the whole run), `#2`/`#4` 16 GB with 1 GB real in
  holes, `#3` 32 GB at `0x7000000000`. `#3` is PartitionAlloc's glued pool: thread parameters and the `new`-allocated objects sit at `0x7000...` (regular half) and `0x7400...` (BRP half, the 2 GB hold of 0110).
  0110's idea ("cppgc large pages") was wrong, but its 2 GB real part is exactly what PA's BRP half needed.
* From the renderer thread: three 32 GB asks (hints `0xb7000000000`, `0x3a2800000000`, `0x13bc00000000`: V8's random-address mask, aligned to 16 GB or more), then two 48 GB-64 KB over-reserves (32 GB + 16 GB alignment),
  then 16 GB (`0x10ec00000000`). That is V8's sandbox falling back from 32 GB to 16 GB. Needs 16 GB alignment (a 4 GB-aligned hole was rejected three times).
* 0.50.224 answered the 32 GB ask with a soft slot at `0x7400000000`, 0.50.225 the 16 GB one: both are PA's BRP half. Sandbox and PA wrote the same pages (BackupRefPtr assertion, 0xEF quarantine reads, then int3).
* All helper restarts after the crash got nothing: the first helper's views are never released at its exit (see Open).

## What it does
* A 32 GB or 16 GB ask with offset 0 that finds no plain slot (switch on) is answered with the real 32 GB view at `0x7800000000` if it exists and has seen < 256 MB of commits (`ios_pa32_share_idle_pool`);
  otherwise it is DECLINED (V8 tries smaller). No more soft slot on top of live pools for these asks.
  Log: `[pa32] patch0112 N MB ask #K shares the idle real 32GB view at ...` / `... declined ...`.
* `ios_vmlog`: the last 96 NtAllocate/NtFree/NtProtectVirtualMemory calls on addresses >= 0x7000000000 and every failure anywhere, printed as `[vmlog]` lines before the `[int3-guest]` dump.

## Not verified / open
* Who owns the idle 32 GB view is unknown; if it ever starts committing, sandbox and owner share pages.
* A dead helper's reservations (the 32 GB views, soft tails, the 4 GB and 2 GB holds) are not given back at exit, so the launcher's automatic restart of the helper cannot work. Needs `ios_bigres` entries tagged with
  the PEB, released from `process_exit_wrapper`, and the two holds recreated. Not done here.
* `[jumbo#8]`/`[jumbo#9]` (48 GB-64 KB) are expected to keep failing; V8 does not mind.

## Rebuild
`cp -R gl-lib-0111 gl-lib-0112; BASE=.../gl-lib-0111/libntdll_unix.a OUT=.../gl-lib-0112 tools/rebuild_ntdll_object.sh virtual signal_arm64`, then `LIB_OVERRIDES=.../gl-lib-0112 tools/stage_runtime.sh`.
