# 0090 JIT pool: the copy of an image its own process unmapped goes back to the freelist

`build/ntdll-unix/virtual_ios.c` (`ios_pool_give_back_copy`, called from `ios_jit_retire_image`). Only active where image retire is on (`MADEIRA_JIT_IMAGE_RETIRE`, which Dock sessions set). Rebuilt with `tools/rebuild_ntdll_object.sh virtual` + `tools/rebuild_gl_objects.sh`.

Why (RDR2, log of 0.50.164): the launcher got to running `Social-Club-Setup.exe` (a 125 MB image whose preferred base 0x140000000 is not available, so it is mapped, unmapped and mapped again), and the pool, 976 MB on this device, ran dry
(`[jit-pool] EXHAUSTED`, the next process could not load its ntdll, the app ended). The first mapping's pool copy stayed in the ledger until the process exit, and the same happened to `Launcher.exe` (3 x 32 MB) and `socialclub.dll` (4 x 6 MB).

Now, when a process unmaps an image it mapped itself, its ledger entry (if it starts exactly at that copy, belongs to the process and holds no other live mapping or FEX code buffer) is cleared from the EC bitmap and put on the freelist with the usual 3 s grace.
Log line: `[jit-image-retire] 0090 gave back ...`. Not verified on a device. Not addressed: the pool copy holds the WHOLE image (a 125 MB installer is mostly resources), and each process keeps its own copy of every library.
