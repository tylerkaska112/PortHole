# 0080 DXMT: CPU-visible buffers backed by a file (opt-in)

`dxmt/src/winemetal/unix/winemetal_unix.c` (`bufswap_*`, `_MTLDevice_newBuffer`); applied by `tools/apply_dxmt_patch.sh`, built into `libdxmt_combined.a` with `MADEIRA_ONLY=winemetal_unix bash vendor/Madeira/build/dxmt-ios/build.sh`.

Why: Rust's load (2026-10-06, five runs) ends at the 6144 MB limit with about 3.4 GB of Metal memory, 2.1 GB of it ~96,000 shared MTLBuffers (meshes), which Metal allocates itself (IOAccelerator, charged in full to phys_footprint, compressed or not; textures were already cut with `d3d11.mipClampBC`, 3.4 -> 1.3 GB, which did not move the wall). Dirty pages of a MAP_SHARED file mapping are not charged (ml1076 canary, ml1077 swap tier).

What: `madeira.cfg buffer-swap-kb = N` (0 = off, the default; or `MADEIRA_BUFFER_SWAP_KB`). A buffer of at least N KB, CPU-visible (shared, default cache mode: write-combined is already stripped by ml1178) and created without memory of its own, gets memory carved out of an unlinked sparse file in the tmp folder (256 MB chunks mapped on demand, size classes, 16 KB pages, hole punched on free) and is created with `newBufferWithBytesNoCopy`; the contents pointer DXMT gets back is that memory. `buffer-swap-mb` (default 8192) caps the live bytes. Anything that fails (file, mapping, cap, Metal returning nil) falls back to Metal's own allocation. Logs `[bufswap] 0080 ...` on start and every 512 MB of growth.

Checked: compiles for iOS; a Mac test (`newBufferWithBytesNoCopy` over a MAP_SHARED file mapping, GPU blit read and write, deallocator) passes.
NOT verified on the iPad. The open question is whether iOS keeps the pages of a no-copy buffer wired and charged anyway (then the footprint does not drop, nothing breaks). What to watch: `[bufswap]` live MB against `[footprint]` phys/compressed and the `tag 100` totals in `[phys-map]`; `refused by Metal` in the `[bufswap]` line (above 0 means Metal rejected file-backed memory); frame rate and stalls (evicted pages are read back from flash).
Try: Engine page of a game: `buffer-swap-kb = 32` with `swap-mb = 16000`.
