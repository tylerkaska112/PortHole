# 0049 - FEX learns about images a program maps itself (Black Ops 3)

**Problem.** After 0048 (log of 0.50.87) Black Ops 3's protection walks its modules: open the system DLL from disk, `NtCreateSection` (SEC_IMAGE), `NtMapViewOfSection` (status 0x4000000e = not at base), then runs code in the clean copy (gdi32.dll at 0x71f1bf0000). `[map-notify] SKIP (no ArbitraryUserPointer)` dropped the notification, so FEX's InvalidationTracker never got the executable range: `NoExec instruction in entry block: 71F1C24C90` -> `Unhandled page fault on execute access` -> NtTerminateProcess(0xc0000005) after ~25 s.

**Change.** `wine/dlls/ntdll/signal_arm64ec.c`, `notify_map_view_of_section`: the missing ArbitraryUserPointer no longer returns (FEX's `NotifyMapViewOfSection` ignores it: `HandleImageMap` reads the PE headers at the address). The `NtQuerySection(SectionImageInformation)` check that follows still skips non-image sections. Logs `[map-notify] 0049 ...` (first 20).

**Rebuild.** `bash vendor/Madeira/build/wine-pe/build-ntdll.sh`, restage. Backup of the shipped file: `$F4_BUILD_ROOT/backup-ntdll-before-0049.dll`.

**Risk.** Any program mapping an image with NtMapViewOfSection directly is now registered with FEX (before: its code could not run). Idempotence of HandleImageMap for an image the loader also registers was not checked.
