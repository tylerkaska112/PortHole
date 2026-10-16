# 0066 - the game's program name in its on-disk spelling (experiment, Black Ops 3)

**Problem.** With every compatibility step done (0045-0064) Black Ops 3's protection still spins at 100% CPU with a frozen register state in guard-trampoline code (save registers, call a guard, restore, jump...; 0.50.108-110 logs), walking kernel32's export names for something that is never found. The only remaining visible difference between this process and a Windows one that the protection could hash: Steam's client passes the program to NtCreateUserProcess in LOWER case (`image=L"...\blackops3.exe"`, `Starting Wine process: ...\BlackOps3.exe` is the Dock's own request), so the PEB's ImagePathName, command line and the main module's BaseDllName read `blackops3.exe`, where on Windows Steam launches `BlackOps3.exe` (the spelling of the file on disk and in the depot).

**Change.** `process_ios.c`, `NtCreateUserProcess`: in the image path and the command line, a final path component equal to `blackops3.exe` (any case) is rewritten to `BlackOps3.exe` (same length, in place). Logs `[exe-case] 0066 image path|command line fixed...`. A general fix (take the real case from the directory entry) is for later if this helps.

**Rebuild.** `tools/rebuild_ntdll_object.sh process`, copy the library over `vendor/Madeira/app/Madeira/libntdll_unix.a`, restage.
