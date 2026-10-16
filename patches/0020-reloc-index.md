# 0020: find a region's relocation blocks without walking the whole table

`vendor/Madeira/build/ntdll-unix/virtual_ios.c` (the "iOS JIT IAT sync" in `NtProtectVirtualMemory`) and the new `ios_reloc_index.h`.

## The problem (Far Cry 6 stuck after Steam login, 2026-10-05)

When a game changes the protection of a piece of one of its program files, the engine syncs that region of the file's pool copy: it re-applies the file's DIR64 relocations over what it copied. It did that by walking the
file's **whole** relocation table, **twice**, for every call. Far Cry 6's `FC_m64d3d12.dll` is 534 MB. The game's copy protection unpacks itself page by page, so it calls `VirtualProtect` tens of thousands of times:
the log showed one thread at 99% CPU in `NtProtectVirtualMemory`, the `[iat-sync]` counter at `#2000` at 02:59:19 and no `#3000` 86 seconds later (about 90 ms a call; 534 MB is about 130,000 pages, so hours).

## The change

A relocation table is a list of blocks, one per 4 KB page, in ascending page order. `ios_reloc_window()` builds an index of the blocks on first use (page address and position, cached per table, checked
on every use against the memory it describes, so another image mapped at the same place is re-indexed) and returns the part of the table that can touch `[off, off + len)` by binary search. It includes the block before the
first page, because an 8-byte DIR64 entry can start up to 7 bytes before a page boundary. The two loops in the engine are unchanged; their start and end pointers are narrowed. A table that is not in ascending order, or cannot be
indexed, gets the old full walk.

Host test: `app/Tests/Reloc/run.sh` (the narrowed walks find exactly the fixups the full walk finds over 4000 random regions, including straddling ones and the ends of the image; unsorted tables are not narrowed; a replaced table is
re-indexed). On a synthetic 64 MB image, calling it page by page as the game does took about 9.6 s with full walks and 2 ms with windows.

## Rebuild

`tools/rebuild_ntdll_object.sh virtual` writes a patched copy of `libntdll_unix.a` to `$F4_BUILD_ROOT/ntdll-lib/`; copy it over `vendor/Madeira/app/Madeira/libntdll_unix.a` (the old one is kept in
`$F4_BUILD_ROOT/backup-before-reloc-index/`) and run `STAGE=$F4_BUILD_ROOT/stage-madeira-update tools/stage_runtime.sh`. Apply the source change with `git -C vendor/Madeira apply ../../patches/0020-reloc-index.patch`.
Engine record: `tools/engine.sh bump` (games that hung now run).
