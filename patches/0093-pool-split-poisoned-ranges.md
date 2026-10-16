# 0093 JIT pool: keep the executable runs of a half-poisoned freed range

`build/ntdll-unix/virtual_ios.c` (`ios_pool_alloc_range_ex`, the `POISONED range` branch; `IOS_POOL_RUN_MIN`). Rebuilt like 0087.

Why (RDR2, logs of 0.50.168): the 1056 MB pool ran dry (`[jit-pool] EXHAUSTED`, the launcher's second process could not load oleaut32 and never opened) while 237 freed ranges, 464 MB, sat unused: every range freed by an exited process has
a few pages that are no longer executable (`[pool-freechk] POISONED AT FREE ... cur=0x3 max=0x3`; the first such page of each range is at the module's `.data`, which is made writable in the pool copy, and a page that was read-write once cannot be
executable again), and the allocator dropped a range as a whole as soon as ONE page was bad (`POISONED range ... dropped, NOT handed out`).

Now such a range is split: every run of still-executable pages of at least 128 KB (`IOS_POOL_RUN_MIN`) stays on the freelist as a range of its own (same grace time); the poisoned pages and shorter runs are dropped.
Log lines: `POISONED range ... splitting off its executable runs (0093)` and `0093 kept N executable run(s), 0x... of 0x... bytes`. Not verified on a device. The freelist holds 256 entries; runs that do not fit are lost, as before.

0.50.170 (a freed range handed out too soon): in the log of 0.50.169 a thread of the first Launcher.exe, killed violently (`kill_thread tid=0208 ... violent=1`) but still running on the host (a killed thread only dies at its next server request),
returned from its wait after its process had been reclaimed and called into the private ntdll copy; a split run covering that copy had already been given to coml2.dll, so the call landed in zeros (`ILL at pc=0x14096395c`) and the app ended.
Before the split these ranges were dropped, which hid the laggard. The runs now wait 60 s longer than the usual 3 s grace before they can be reused (`IOS_POOL_RUN_QUARANTINE_SEC`). That is a bound by time, not a guarantee: a thread that lives longer
still crashes. The real fix is to make a killed thread leave its guest code at once, or to count the live threads of a process before its ranges are freed.
