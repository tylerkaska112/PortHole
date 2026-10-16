# 0098 JIT pool: wait for memory that is on its way instead of failing the load; quarantine 60 s -> 10 s

`build/ntdll-unix/virtual_ios.c` (`ios_pool_alloc_range`, `ios_pool_pending_bytes`, `IOS_POOL_RUN_QUARANTINE_SEC`). Rebuilt like 0087.

Why (RDR2, log of 0.50.174's predecessor 0.50.173): the first Launcher.exe exited at about +25 s and freed 200 MB (RECLAIM 83 ranges 0xc620000), but those ranges were in the 3 s grace plus 0093's 60 s quarantine, so the second Launcher.exe,
loading socialclub.dll (6 MB) at about +70 s, got `[jit-pool] EXHAUSTED ... freelist=256`, the module stayed without a pool copy and the first call into it died (`AV EXEC of 0x71d2799db0`).
The quarantine (added because a killed-but-still-running thread of a dead process once called into a reused range) starved exactly the launch that needed the memory.

Now: the quarantine is 10 s (that thread ran for under 2 s after its process was reclaimed), and when a request cannot be served but the freelist holds at least that many bytes still in grace/quarantine, the allocation waits
(250 ms steps, at most 30 s, the caller holds the virtual mutex meanwhile) and tries again. Log line: `[jit-pool] 0098 waited N ms for freed memory still in its grace`.
Not verified on a device. The proper fix for the dead process's runaway threads is still to stop them (or count them before the ranges are freed).
