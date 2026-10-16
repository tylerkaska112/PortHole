# 0024 - 32-bit hard error text, system-DLL memory calls in the log, and WriteProcessMemory on yourself

**Problem.** Ubisoft Connect's client (`upc.exe`, 32-bit) raises `NtRaiseHardError` with a status of its own (0x50000018, four parameters, the first two strings) right before it ends itself with exit code 0xdeadc0de. Wine's WoW64 stub only printed the pointers.

**Change.** `wine/dlls/wow64/system.c`, `wow64_NtRaiseHardError`: also print each parameter, and the strings the mask marks (32-bit UNICODE_STRING, converted through the guest window). Still returns STATUS_NOT_IMPLEMENTED, as before.

**Rebuild.** `PATH=vendor/Madeira/toolchains/llvm-mingw-*/bin:$PATH make -C vendor/Madeira/wine/build-aarch64 dlls/wow64/aarch64-windows/wow64.dll`, then `aarch64-w64-mingw32-strip --strip-debug` and cut the file to the end of its last section (458752 bytes; the build leaves 64 KB of trailing data the shipped file lacks), and put it at `vendor/Madeira/app/Madeira/aarch64-windows/wow64.dll`. Sections match the shipped file apart from +0x114 of code and +0x80 of strings. Restage with `tools/stage_runtime.sh`.

**Engine.** Logging only, recorded with `tools/engine.sh accept`.

**Added in 0.50.62.** `wine/dlls/wow64/virtual.c`: `[wow-vm]` lines for NtProtectVirtualMemory, NtWriteVirtualMemory and NtQueryVirtualMemory (basic information) calls on guest addresses 0x70000000 and above (system-DLL range), with arguments and result; first 300 of each. Shows what a program that patches system functions does and what it is told.

**Fix added in 0.50.63 (called 0027 in the code comment; same files).** `wow64_NtWriteVirtualMemory` in `wine/dlls/wow64/virtual.c`: when the target is the calling process (pseudo handle, or a real handle whose process id is ours), the bytes are copied straight to memory, region by region, provided each page is already writable (queried), and the emulator is told with `BTCpuNotifyMemoryDirty`. Before, every such write went to the Wine server, which on this port cannot write into the app's own memory and answered STATUS_ACCESS_DENIED (c0000022): all 58 inline hooks (`e9 rel32` over system DLL functions) the Ubisoft Connect launcher tried failed, and its client stopped with `Error at hooking API "LdrFindResource_U"`. Other targets keep the server path. The `[wow-vm] write(self)` log line marks the new path. Only the 32-bit (wow64) layer is changed; 64-bit programs still use the server path.

**Added in 0.50.65.** The in-process write now also does what Windows' `WriteProcessMemory` does for a read-only or execute-only page: it makes the range writable (`PAGE_EXECUTE_READWRITE` for an execute page, else `PAGE_READWRITE`), with the same BTCpu notifications as `wow64_NtProtectVirtualMemory`, writes, and puts the old protection back. The one hook write that failed with c0000005 in the 0.50.63 log (ntdll+0x4ee90, a page the hooker had not made writable) needed it.
