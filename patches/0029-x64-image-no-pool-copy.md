# 0029 - plain x64 images do not get a JIT pool copy (opt-in)

**Problem.** Making any image page executable copies the whole image into the JIT pool and remaps it over the original address. For ARM64EC and ARM64 images that is the code that runs. For a PLAIN x64 image in an ARM64EC session (a game's own files) nothing runs from the copy: the emulator reads the x64 bytes from the image address and runs its translation out of the pool (`ios_jit_mapping_is_hybrid`'s comment calls it "a dead copy"). Far Cry 6's `FC_m64d3d12.dll` is a 534 MB image (467 MB executable sections): the copy took 510 MB of a 1120 MB pool, and Ubisoft Connect's helper processes then died with `JIT pool exhausted` / `EXEC ALLOC FAILED`.

**Change.** `build/ntdll-unix/virtual_ios.c`: `ios_x64_image_is_host_data()`, used in `mprotect_exec` next to the 32-bit rule of ml1030: for a SEC_IMAGE view with machine 0x8664 and a zero `CHPEMetadataPointer` (an ARM64EC image is also 0x8664, but has CHPE metadata), in an ARM64EC session, outside any WoW window, PROT_EXEC is dropped (no host meaning), like the i386 case. Only when `MADEIRA_X64_IMAGE_DATA=1` (Settings > Engine > Memory > "Big x64 programs in the code pool"); default off, so nothing changes unless asked. Logs `[x64-image] 0029 ...` for the first 24 images.

**Rebuild.** `tools/rebuild_ntdll_object.sh virtual`, copy the library over `vendor/Madeira/app/Madeira/libntdll_unix.a`, restage.

**Risk.** SMC (self-modifying code) detection for x64 images used to run against the pool copy ("backing stays non-exec, pool copy keeps X"); with no copy the emulator's own page-protection tracking is what remains, as it already is for 32-bit images. Unverified for x64 on a device: that is why it is opt-in.
