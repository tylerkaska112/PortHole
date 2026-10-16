# 0111 The third 32 GB ask is served from a hole, not from a soft slot on top of the pools (opt-in, with 0105)

`build/ntdll-unix/virtual_ios.c`, only with the 0105 switch (`MADEIRA_PA_POOL32_SOFT=1` / `pa-pool32-soft = 1`).

## Why (RDR2 log of 2026-10-11 22:57, build 0.50.224)
0110 worked as written: 2 GB real at `0x7400000000`, band `[0x7480000000,0x7800000000)`, 126 threads, no FEXAlloc failures. Four reserves were served (`[jumbo#1]` 32 GB real at `0x7800000000`,
`#2`/`#4` 16 GB with 1 GB real in holes, `#3` 32 GB at `0x7000000000` with its 4 GB + 2 GB real parts). Then thread `0374`, named `Chrome_InProcRendererThread` (the in-process renderer), asked for a FIFTH range:
`[jumbo#5] size=0x800000000 hint=0x7e1800000000`. Every plain slot failed and the soft-slot fallback granted `0x7400000000`: the BRP half of the 32 GB pool at `0x7000000000` and the 2 GB large-page hold,
plus the band. The owner of that range then committed `0x7400428000` (a 24 KB slot) over memory the other allocator already used; the same thread read a 0xEF "quarantined" object
(`AV READ of 0xefefefefefefeff3`, BackupRefPtr zaps freed slots with 0xEF) and the main thread died in PartitionAlloc's free path with `[brp-contain] BackupRefPtr refcount assertion` (int3, 0x80000003, "slotsize" on the stack).

## What it does
In the soft-slot fallback, for an exact 32 GB ask with offset 0 and the switch on, `ios_pa32_soft_back2()` places the range where the map has its biggest hole, preferably on a 4 GB-aligned
address (V8's sandbox and cages want that), with 2 GB real and the rest soft. The caller is told it got 32 GB. If no aligned hole is big enough the unaligned one is used; if none, the old slot grant
runs. Log: `[pa32] patch0108 ... (patch0111: aligned)` and `[pa32] patch0111 32GB ask #N served from a hole at ...`. The jumbo census also runs the module owner search once for this ask
(`[pool-owner] ...`), which names the module whose globals hold each granted base.

## Not verified / open
Nobody knows yet what the fifth ask belongs to (V8 sandbox? a second PartitionAlloc address space?); the `[pool-owner]` lines are there to say. 30 GB of the grant is soft and overlaps real
views: if its owner commits beyond the 2 GB real part, `[soft-pool] COLLISION` lines will show it. The hole costs 2 GB of the furniture window.

## Rebuild
`cp -R gl-lib-0110 gl-lib-0111; BASE=.../gl-lib-0110/libntdll_unix.a OUT=.../gl-lib-0111 tools/rebuild_ntdll_object.sh virtual`, then `LIB_OVERRIDES=.../gl-lib-0111 tools/stage_runtime.sh`.
