# 0038 - SetThreadIdealProcessorEx reports success (CS2 embree crash)

**Problem.** Counter-Strike 2 died every run (after 95-215 s) in `embree3.dll+0x1bec`. `[av-mem]` (0.50.73) showed the message about to be written to `std::cerr`: `Warning: SetThreadAffinityMask failed`; the last call before the fault in the log of 0.50.75 was `fixme:thread:SetThreadIdealProcessorEx (...): stub`. Wine's kernelbase `SetThreadIdealProcessorEx` is a stub returning FALSE with ERROR_CALL_NOT_IMPLEMENTED; Embree's thread-pinning code reads that as a failure and prints a warning on `std::cerr`, whose object (RCX, msvcp140.dll data) is all zeros in the game's view of the runtime, so the print dereferences a null vbptr. Patches 0037 (affinity) were aimed at the wrong call; the `[affinity]` log showed only two early requests for the current thread.

**Change.** `wine/dlls/kernelbase/thread.c`: `SetThreadIdealProcessorEx` fills `previous` with group 0 / processor 0 and returns TRUE (nothing can be scheduled on a chosen processor on iOS anyway).

**Rebuild.** `DEST=/tmp/kb bash vendor/Madeira/build/wine-pe/build-modules.sh kernelbase`, put `kernelbase.dll` at `vendor/Madeira/app/Madeira/arm64ec-windows/kernelbase.dll`, restage. A rebuild of the UNMODIFIED source differs from the shipped file by only 6 bytes (timestamp/checksum); the patched one differs in about 10% of its bytes (code after the changed function moved). Backup of the shipped file: `$F4_BUILD_ROOT/backup-kernelbase-before-0038.dll`.

**Not fixed.** The zeroed `std::cerr`: any other message printed through it would crash the same way.
