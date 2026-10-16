# 0048 - a raw file view that starts with MZ is not an image (Black Ops 3)

**Problem.** With 0047 the hang became a visible fault (`[mach-deliver] 0047 fault at 0x7076f20000 ... holds virtual_mutex`, log of 0.50.86): `memmove` in `mprotect_exec` (the "copy the whole PE image into the JIT pool" step) read past the end of a view. The game maps a Windows DLL from disk as a plain section (`[sc] ssn=0x28` NtMapViewOfSection, MaximumSize 1 MB, PAGE_EXECUTE_READ) to compare it with the loaded one. The backward MZ scan in `mprotect_exec` found the MZ header at the view's start and took SizeOfImage (0x118000, the loaded size) as the extent; the view is 0x100000 long, so the copy ran 0x18000 bytes into unmapped memory.

**Change.** `virtual_ios.c`, `mprotect_exec`, before the anonymous-RWX decision: when an MZ/PE header was found, check that the claimed image's last page is mapped and readable (`mach_vm_region`). If not it is a raw file view: log `[mprotect-exec] 0048 ...` (first 12), `mprotect(base, size, PROT_READ)` and return 0 (nothing executes a file view; no pool copy, no pool space used).

**Rebuild.** `tools/rebuild_ntdll_object.sh virtual server`, copy the library over `vendor/Madeira/app/Madeira/libntdll_unix.a`, restage.
