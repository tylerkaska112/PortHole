# 0028 - a 32-bit child whose ntdll copy fails stops alone instead of killing the app

**Problem.** With the JIT pool full, `[child-ntdll] JIT pool exhausted (need 0x118000 ...)` then `ntdll copy FAILED - falling back to SHARED ntdll`. A 32-bit child cannot run on the shared ntdll: its WoW64 hook pointer (`[x21+0x6d0]` at the end of the loader's init, ntdll+0x44e1c) is never set, so it calls NULL, the exception dispatcher enters a critical section that does not exist (`RtlEnterCriticalSection(NULL)`, fault address 0x20) and faults again for ever. After 2000 identical redeliveries the storm guard (`ml465`) calls `task_terminate(mach_task_self())`: the WHOLE APP dies. Seen with Ubisoft Connect's helper processes (`UplayWebCore.exe --type=gpu-process`) on Far Cry 6, with the pool at 1.1 GB.

**Change.** `build/ntdll-unix/loader_ios.c`: when the per-child ntdll copy fails for a 32-bit child, `CHILD_BOOT_FAIL` (like the other boot failures) so only that child ends. 64-bit children keep the old fallback.

**Rebuild.** `tools/rebuild_ntdll_object.sh loader` (the script now knows `loader`), copy the library over `vendor/Madeira/app/Madeira/libntdll_unix.a`, restage.

**Not a fix for the pool.** The pool is two allocators facing each other (image copies up from the bottom, FEX code buffers down from the top); a bigger pool just gets filled by the code buffers. Far Cry 6 alone copies a 534 MB image into it.
