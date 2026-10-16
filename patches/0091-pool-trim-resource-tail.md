# 0091 JIT pool: no pool copy for the resource tail of a huge image

`build/ntdll-unix/virtual_ios.c` (`ios_pool_trim_image`, `ios_pool_trim_note/forget`, `ios_pool_in_trimmed_tail`; used in `mprotect_exec` and `delete_view`). Rebuilt like 0087/0090.

Why (RDR2, log of 0.50.165, Rockstar launcher): the pool (1120 MB) ran dry again while the launcher restarted itself; the new Launcher.exe could not load oleaut32.dll, and the Chromium delay-load hook ended it (exit 0xFFFF7001, "never opens again").
Social-Club-Setup.exe is mapped twice (125 MB each) although its code section is 180 KB: the pool keeps a copy of the WHOLE image, payload included.

Now an image of at least 16 MB whose last section holds the resource directory and is at least 8 MB gets a pool copy that ends where that section starts (0.50.167: sections after the resource section may follow if none is code and they total under 4 MB: MSVC puts .reloc there). Addresses past the end stay on the ordinary mapping (not translated), a
request to make them executable is answered as plain data, and the "already copied" check accepts the cut size. Log line: `[jit-pool] 0091 ...: pool copy cut to ...`. `MADEIRA_POOL_TRIM=0` turns it off.
Not verified on a device, and not known to apply to Social-Club-Setup.exe (its section layout was not available here): if its payload is not in a trailing .rsrc nothing changes and the log has no `0091` line.

0.50.167: the first version needed the resource section to be the LAST one, which an MSVC image never has (.reloc follows), so nothing was cut in the 0.50.166 log. The section table of the first big images is now logged: `[jit-pool] 0091 big image ... section .text va=... size=... flags=...`.

0.50.168 (the cut copy used to read its relocation table past its own end): `mprotect_exec` applies the image's DIR64 relocations to the pool copy and read the table from the copy, where `.reloc` (after the cut) no longer is.
With 0.50.166/167 it read whatever followed in the pool, applied wild fixups, and in the log of 0.50.167 read 0x4d5dc000 bytes past the pool's start: a fault in a thread that holds `virtual_mutex` (RDR2's launcher froze on "Connecting to Rockstar services").
Now the table is read from the mapping the copy was made from, fixups past the copy are skipped, and no relocation info is recorded for later re-application when the table is not in the copy.
