# 0025 - Windows' hot-patch prologue in the 32-bit system DLLs (experiment)

**Problem.** Ubisoft Connect's client (`upc.exe`, 32-bit) shows "Error at hooking API LdrFindResource_U" (a `NtRaiseHardError` message box: text, caption, icon 0x10, timeout -1) and ends itself with exit code 0xdeadc0de. It cannot hook `ntdll!LdrFindResource_U`. In our i386 ntdll that function starts `66 90 55 89 e5 ...` behind `cc cc cc cc cc`; Windows' starts `8b ff 55 8b ec ...` behind the same padding. A hook library written for Windows may test for `8b ff`.

**Change.** `patches/0025-i386-hotpatch-prologue.py` swaps `66 90` for `8b ff` (both no-ops) at the entry of every exported function of ntdll, kernel32 and kernelbase that begins `66 90` (785 in ntdll). Output goes to `$F4_BUILD_ROOT/ec-out-i386/`, which `tools/stage_runtime.sh` copies over the 32-bit farm.

**Rebuild.** `python3 patches/0025-i386-hotpatch-prologue.py vendor/Madeira/app/Madeira/i386-windows $F4_BUILD_ROOT/ec-out-i386`, then `tools/stage_runtime.sh`.

**Engine.** Changes what 32-bit programs see: `tools/engine.sh bump`. Not yet known to be the cause; if it is not, remove it.
