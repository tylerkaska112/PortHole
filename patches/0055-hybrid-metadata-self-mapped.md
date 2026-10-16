# 0055 - ARM64EC images a program maps itself get their hybrid-metadata slots (Black Ops 3)

**Result of 0.50.99** (ntdll excluded from the sysx64 redirect): the protection now unmaps the clean ntdll (`[sc] #3`) and goes on to gdi32 (`#4-#6`, the x64-compatible build via `[sysx64] 0050`), calls into it and dies: `[thunk-slot] WEDGE pc=0x0 ... exec-relative slot @0x12cf61480 = 0x0`, lr gdi32.dll+0x544e4: native ARM64EC code of the clean copy calls through a dispatch slot that is zero, because only the loader (`update_load_config` -> `arm64ec_update_hybrid_metadata`) fills `__os_arm64x_dispatch_call` & co.

**Change.** `wine/dlls/ntdll/signal_arm64ec.c`, `notify_map_view_of_section`: for an image section whose ArbitraryUserPointer is missing (mapped by the program, not the loader) and whose machine is AMD64, if its load config has CHPEMetadataPointer, call `arm64ec_update_hybrid_metadata` (its NtProtectVirtualMemory round trip syncs the pool copy). Logs `[map-notify] 0055 ...`.

**Rebuild.** `bash vendor/Madeira/build/wine-pe/build-ntdll.sh`, restage. Backup: `$F4_BUILD_ROOT/backup-ntdll-before-0055.dll`.
