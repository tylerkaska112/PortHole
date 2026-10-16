# 0097 JIT pool: the resource cut (0095) also applies to Wine's DLLs

`build/ntdll-unix/virtual_ios.c` (`ios_pool_trim_image`: header-size guard 0x4000 -> 0x20000).

Why (RDR2, log of 0.50.172): `pool copy cut` appeared only for Launcher.exe (twice) and Social-Club-Setup.exe; shell32.dll was still copied whole 10 times (93 MB), kernelbase 16 times, user32 13 times.
Wine's DLLs have SizeOfHeaders 0x10000 (64 KB, section alignment 0x10000), and the guard `hdr_size > 0x4000` rejected them. Now up to 0x20000 is accepted.
(shell32.dll: 8 sections, `.rsrc` at 0x120000 = 8.7 MB of its 9.5 MB, `.reloc` 6.6 KB after it.) Unchanged otherwise (Dock sessions only, 1 MB images with 256 KB of resources). `MADEIRA_POOL_TRIM=0` turns it off. Not verified on a device.
