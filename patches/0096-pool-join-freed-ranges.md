# 0096 JIT pool: freed ranges that touch are joined

`build/ntdll-unix/virtual_ios.c` (`ios_pool_alloc_range_ex`; new `split` field on the freelist entries). Rebuilt like 0087.

Why (RDR2, log of 0.50.171): `[jit-pool] EXHAUSTED (image ...+0x601000): want=0x608000 bump=0x39b90000/0x46000000 ... freelist=256`. The 6 MB socialclub.dll copy was refused while the freelist was FULL of small pieces: images are freed one at a time, so neighbours stayed
separate entries (and the runs of 0093 cut them up further). The module then stayed without a pool copy and its first call died with `AV EXEC of 0x71d596abe0`, ending the second Launcher.exe.

Now, before every search, the freelist is sorted by offset and entries that touch are joined when both are past their grace (a run still in its 60 s quarantine is not joined). A joined range that contains a poisoned page is split again where it is examined (0093),
without a new quarantine when its parts already went through one (`split` flag). Log line: `[jit-pool] 0096 joined N touching freed range(s); freelist now M`. Not verified on a device. The pool is still a fixed size per launch (1120 MB in this log) and
every process has its own copy of every library: if it still fills up, sharing the copies between processes is the remaining big step.
