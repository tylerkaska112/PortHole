# 0087 each process's emulator learns about the images that process maps

`build/ntdll-unix/virtual_ios.c` (`ios_jit_add_mapping`, `unixcall_ios_push_jit_aliases`, `ios_jit_reclaim_process`; new `ios_alias_cbs` table). Rebuilt with
`tools/rebuild_ntdll_object.sh virtual` (`BASE=` the previous library), then `tools/rebuild_gl_objects.sh` (`NTDLL_BASE=` that copy).

Why (Red Dead Redemption 2, 2026-10-08, log of 0.50.160): Launcher.exe (pid 0114) died with `c0000005` at address 0 in `d2d1.dll`. The faulting RIP was the x64 delay-load stub for
`DWriteCreateFactory` inside the ARM64EC d2d1. FEX logged `[iOS-xquery] MISS ... rev=<same address>` and `NoExec instruction in entry block`: its alias table did not contain d2d1.
Cause: the callback that pushes image mappings to an emulator is ONE global, replaced by every process that starts an emulator. The service process (0110) started its emulator while
0114 was still loading libraries, so d2d1, which 0114 mapped afterwards, was pushed to 0110's emulator and 0114's own never heard of it. Most ARM64EC code never goes through FEX, which
is why this only showed on the x64 stubs inside an EC image.

Now every registering process's callback is also kept by PEB, and an image is pushed to the emulator of the process that maps it as well as to the shared one (nothing that was delivered
before is withheld). The entry is removed when the process exits, before its pool copy is reclaimed. Log line: `[alias-push] 0087 image ... goes to its own emulator`.
Unverified on a device. A slot is 32 processes; beyond that a process keeps only the shared callback, as before.

## Second part (0.50.163): an emulator holds 256 images

Log of 0.50.162: the Rockstar service process (`RockstarService.exe`, the one `services.exe` starts) died with `c0000005` at address 0 every time (also in 0.50.161 and 0.50.160), right after
`[jit-alias] ml1106 IosAliasEntries FULL (256 entries): image ... (rsaenh.dll) NOT registered`. Same mechanism as d2d1: an image the emulator was not told about cannot run its x64 stubs.
The table is FEX's, 256 entries per emulator, and a new emulator was handed EVERY other process's images at start (the whole Steam client is a dozen processes with 20-100 DLLs each), so
a small service process started with the table already full. The launcher then restarted the service (start/stop/start...), every attempt left more in the pool, and at 896 MB the pool
ran dry (`[jit-pool] EXHAUSTED`), a new process could not load its ntdll and the app ended on the `[redeliv] ... terminating process`.

Now a process's own images always go to its emulator; images of OTHER processes are added only until the emulator holds 192 (`IOS_ALIAS_FOREIGN_CAP`), both when it starts and when a later image
is pushed to the shared callback. Nothing changes for a process whose total stays under that. Log lines: `[alias-push] 0087 ... left out`, `... already holds N images`.
Not verified on a device. The real fix would be a larger table in FEX (`kMaxEntries` in `FEX/Source/Windows/ARM64EC/IosJitAlias.cpp`); that needs a rebuild of the emulator DLL.
