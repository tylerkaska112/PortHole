# 0114 The sandbox carve runs once; V8's later 16 GB / 8 GB asks are served from a hole (opt-in, with 0105)

`build/ntdll-unix/virtual_ios.c`, only with the 0105 switch.

## Why (RDR2 log of 2026-10-11 23:48, build 0.50.227; screenshot: "The Rockstar Games Launcher timed out loading both its online and offline content")
* 0113 worked: `[jumbo#20]` 8 GB sandbox placeholder at `0x7e00000000`, then three 1 GB reserves (V8's external pointer tables) from holes. The helper ran, created its threads, and the launcher's error changed from
  "CEF crashed" to a load timeout.
* V8 then kept asking, from the same code that reserved the sandbox: 16 GB (ten random 4GB-aligned hints, each again without a hint), then 8 GB (the same). Each 8 GB ask re-ran 0113's carve, which released the
  32 GB view's remains and reserved its lower 24 GB again: whatever the view's other holder (the second PartitionAlloc instance: BRP half at `0x7c00000000`) had committed in the meantime was thrown away. It wrote
  there again and took a BUS fault (`0x7c00405660`, "ANONYMOUS, NEVER RESIDENT", in the re-reserved `0x7800000000+0x600000000` view). The "idle" claim of 0112 was true only until the helper's second PA instance started.

## What it does
* The carve runs once. Later 8 GB asks do not touch the view.
* A 16 GB or 8 GB reserve that failed everywhere else is served by `ios_pa32_soft_back2`: a 4GB-aligned real part of 1 GB in the biggest hole, the rest soft (as 0108 did for PartitionAlloc's random-hint asks).
  Log: `[pa32] patch0114 N MB reserve served from a hole at ...`.

## Not verified / open
* If that ask is a placeholder reservation, V8's later splits beyond the 1 GB real part will fail.
* Dead helpers still leak their views at exit; the launcher's restarts cannot work.

## Rebuild
`cp -R gl-lib-0113 gl-lib-0114; BASE=.../gl-lib-0113/libntdll_unix.a OUT=.../gl-lib-0114 tools/rebuild_ntdll_object.sh virtual`, then `LIB_OVERRIDES=.../gl-lib-0114 tools/stage_runtime.sh`.
