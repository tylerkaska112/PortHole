# 0071 deep stack snapshots in the timeline (diagnostic, Black Ops 3 only)

`server_ios.c`. The 0070 timeline showed Black Ops 3's main thread at 100% CPU from about 1 s, in frames around rbp ...f100-...f390, until at 12.9 s it was inside the frame (rbp ...c540, rsp ...c440) of the endless loop, 12 KB deeper, with everything in that frame (the five constants, the table, the state variable) already set. The entry happened between two samples. A sample whose rsp is more than 0x800 below the lowest rsp seen so far now saves 0x3400 bytes (up to 16 times), enough to hold the whole call chain from the caller's frame down to the loop's.

**0.50.118.** The first run of 0.50.117 never took a deep snapshot: the lowest-rsp test was seeded by a sample of a native thread (rsp `0x102144187`) at the start, so nothing was ever deeper. Only game stacks (`0x70........`) count now, and a frame with rbp ending in `c540` (the loop's, the same in every run so far) also takes a deep snapshot.
