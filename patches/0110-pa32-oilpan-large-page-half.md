# 0110 Oilpan's upper half is real too; the band moves up to 0x7480000000 (opt-in, with 0105)

`build/ntdll-unix/virtual_ios.c`, only with the 0105 switch.

## Why (RDR2 log of 2026-10-11 22:46, build 0.50.223)
0109 fixed the address-space budget: `[fex-arena] PUBLISHED [0x7400000000,0x7800000000)`, `[cage] 0109 no 8GB holdback`, 1 GB real parts, 126 threads with no `FEXAlloc could not allocate` and no thread-init failures,
the furniture window at 6.8 GB free. The browser host then still died with an int3 in `libcef.dll` (`0x73d2b7580a`): a commit of `0x7400002000` was refused (`0xc0000019`) with `0x7400000000` as the region base
(`R15`) and `0x74001fc000` / `0x7400200000` as its progress on the stack.

`0x7400000000` is exactly 16 GB into Oilpan's 32 GB reservation (`[0x7000000000,0x7800000000)`, answered by `ios_pa32_cage_grant` with only the first 4 GB real). cppgc keeps its large-object pages in the
upper half of the caged heap, so the Oilpan caged heap needs the START of the upper half to be committable. That is where the emulator's band began.

## Change
* `[0x7400000000,+2GB)` is held at start-up and made a real reserved view when Oilpan's ask is served (`[pa32] patch0110 upper half of Oilpan's reservation`).
* The emulator's band moves to `[0x7480000000,0x7800000000)` (14 GB, was 16 GB).

## Not verified
Whether 2 GB is enough for the large-page half, and whether 14 GB is enough band for ~126 threads (the 16 GB one was not full at the end of the 22:46 run).

## Rebuild
`BASE=.../gl-lib-0109/libntdll_unix.a OUT=.../gl-lib-0110 tools/rebuild_ntdll_object.sh virtual`, then `LIB_OVERRIDES=.../gl-lib-0110 tools/stage_runtime.sh`. The build root is now `~/porthole-build-root`
(the build drive `/Volumes/MadeiraWork` refused writes while reporting 960 MB free).
