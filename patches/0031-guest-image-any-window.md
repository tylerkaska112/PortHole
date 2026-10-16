# 0031 - i386 images of ANY guest window are host data (not only the caller's)

**Problem.** The ml1030 rule (`ios_guest_image_is_host_data`) drops PROT_EXEC for i386 image views so they are not copied into the JIT pool, but it asked `ios_wow_in_window()`, which is the CALLER's window. When a 32-bit process starts another, the child's views are protected from the parent's side and the answer was no: every i386 image of the child (unnamed `(?)` copies in windows 0x72-0x79) went to the pool - about 230 MB over a Ubisoft Connect run - and `libcef.dll` (196 MB) failed with `JIT pool exhausted`.

**Change.** `build/ntdll-unix/virtual_ios.c`: also accept an address inside any live window (`ios_wow_addr_in_any_window`); the same for the plain-x64 rule of patch 0029's exclusion.

**Rebuild.** `tools/rebuild_ntdll_object.sh virtual process`.
