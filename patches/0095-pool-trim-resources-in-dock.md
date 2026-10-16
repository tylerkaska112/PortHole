# 0095 JIT pool: cut the resource tail of every sizeable image in a Dock session

`build/ntdll-unix/virtual_ios.c` (`ios_pool_trim_image`, extends 0091; `ios_jit_image_retire_on_for_trim`). Rebuilt like 0087.

Why (RDR2, log of 0.50.170): the pool was 672 MB that run (`ml1036: no hole fits a 1152MB pool - SHRINKING to 672MB`: the size depends on where the system happens to have put other mappings, 1152, 1136, 1120, 1056 and 976 in earlier runs)
and ran dry (`EXHAUSTED`) while the first Launcher.exe was still loading. Every process has its own copy of every library it loads; shell32.dll is 9.5 MB of which 8.7 MB is resources, 11 copies = 103 MB.
Measured on the farm's ARM64EC DLLs: 97 of them have a resource section followed by nothing executable; kernelbase.dll (1.9 of 3 MB), user32.dll, cryptui, comdlg32, winmm, comctl32, crypt32 follow shell32.

In a Dock session (`MADEIRA_JIT_IMAGE_RETIRE` on) the 0091 rule now applies to every image of at least 1 MB whose resource section is at least 256 KB (and is followed only by small non-code sections), not just to 16 MB images with 8 MB of resources.
Other sessions are unchanged. `MADEIRA_POOL_TRIM=0` turns all of it off. Not verified on a device.
