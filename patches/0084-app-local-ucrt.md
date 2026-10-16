# 0084 an x64 program's own ucrtbase.dll no longer replaces the system one

`wine/dlls/ntdll/unix/file.c` (`ios_app_ucrt_alt_name`, used in `NtCreateFile` next to the sysx64 redirect of patch 0050). Rebuilt with `tools/rebuild_ntdll_object.sh file`
(stack it on the OpenGL library with `BASE=<lib>`), then `tools/rebuild_gl_objects.sh` for the combined copy. Host test: `app/Tests/Ucrt/run.sh`.

Why (Red Dead Redemption 2, 2026-10-08): Rockstar's launcher folder holds its own x64 `ucrtbase.dll`. The ARM64EC emulator DLL (`xtajit64.dll`) imports the C runtime through
API-set names that resolve to `ucrtbase.dll`, and the loader searches the program's folder before System32, so for `RockstarService.exe install` the emulator got the program's x64
copy. The loader then called its entry point natively (the emulator does not exist yet): `ILL at pc=...` in `ucrtbase.dll+0x8980`, exit `0xC000001D`. One `ucrtbase.dll` serves a
whole process, so the fix is to serve any copy outside the system folders from the ARM64EC build in `sysx64`. Only for x64 processes and plain reads. Log line: `[ucrt] 0084`.

`MADEIRA_APP_LOCAL_UCRT=1` (environment, or `env.MADEIRA_APP_LOCAL_UCRT = 1` in a game's lines) keeps the program's own copy.
Unverified on a device. If another game that ships its own ucrtbase.dll misbehaves after this, that switch is the first thing to try.
