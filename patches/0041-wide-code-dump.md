# 0041 - 12 KB of guest code around the faulting call (diagnostic)

Black Ops 3's `call r10` (r10 = 0) follows a walk over ALL 1426 export names of kernelbase.dll (RDI = NumberOfNames, RSI/RBX/R14 = the export tables) that found no name with the wanted hash (RAX = 0xc5109281492f21f2): the game looks up a function Wine's kernelbase does not export, gets 0 and calls it. `signal_arm64_ios.c`: once per run, `[x86_code] wide <addr>: <hex>` for the page of the call site, 8 KB before and 12 KB after, so the hash loop can be read and the name recovered. Logging only.
