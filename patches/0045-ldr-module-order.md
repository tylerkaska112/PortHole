# 0045 - module list order like Windows (Black Ops 3 crash)

**Problem.** Black Ops 3 crashed ~22 s in at `call r10` with r10 = 0. Decoded: its protection finds ntdll as the FIRST entry of the PEB's InInitializationOrderModuleList (Windows: ntdll, kernelbase, kernel32, ...) and looks `NtCreateSection` up in its export table. Our list was kernelbase, kernel32, ucrtbase, xtajit64, **ntdll** (ntdll is attached last because it imports the emulator DLL), so it scanned kernelbase's 1426 export names, found nothing, and called the null result (NtCreateSection's 7 arguments were already set up; R15 = file handle 0x64). `[peb-lists]` (patch 0044) showed the lists. InLoad/InMemory order also had xtajit64 and ucrtbase between ntdll and kernel32 (Windows: exe, ntdll, kernel32, kernelbase).

**Change.** `wine/dlls/ntdll/loader.c`, `process_attach`: ntdll is inserted at the HEAD of the init-order list; kernelbase and kernel32 are moved right behind ntdll in the load and memory order lists (kernel32 first, as on Windows). Helpers `ldr_name_is`, `ldr_find_by_name`.

**Rebuild.** `bash vendor/Madeira/build/wine-pe/build-ntdll.sh` (writes app/Madeira/arm64ec-windows/ntdll.dll, padded), restage. Backup of the shipped file: `$F4_BUILD_ROOT/backup-ntdll-before-0045.dll`.

**Risk.** Every game sees the new order (closer to Windows). Detach order of DLL_PROCESS_DETACH follows the init list: ntdll is now detached last, which is correct.
