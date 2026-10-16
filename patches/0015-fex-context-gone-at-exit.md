# 0015: don't touch the translator's context after it is gone (game exit)

`vendor/Madeira/app/Madeira/arm64ec-windows/xtajit64.dll` (FEX, the x86-64 translator). Found from Factorio started through Steam's client (a child process),
which could never finish exiting: when the game quits, Wine unmaps its memory, every unmap reports to FEX's invalidation tracker, and by then the FEXCore
context had been destroyed and its memory zeroed. The tracker's virtual call through the context's null vtable read address `0xf0`:

    [mach_exc] UNHANDLED  pc=libarm64ecfex.dll+0x12b9e8  addr=0xf0     (FEX::Windows::InvalidationTracker::InvalidateIntervalInternal)

Nothing handles that fault, the process stays half-dead, and Valve's client never sees the game end, so it never runs its upload of Steam Cloud files.
Nothing needs invalidating once the context is gone (no translated code is left to protect), so the call is skipped.

## Two forms of the same change

* **Source** (`0015-fex-context-gone-at-exit.patch`, `FEX/Source/Windows/ARM64EC/Module.cpp`): `ContextIsAlive()` (the global context pointer is non-null and the
  object's first word, its vtable, is non-zero) is checked in all seven `Notify*` / flush entry points before they reach the tracker.
* **Shipped binary** (`0015-xtajit64-context-guard.py`): the same check applied directly to the one function that faulted, in the `xtajit64.dll` that shipped up to
  engine r2 (it refuses any other input, so the result is the same bytes every time). The function's first instruction becomes a branch to a six-instruction guard in the unused
  tail of `.text`; if the context's vtable is zero it returns at once, otherwise it runs the displaced instruction and continues. Nothing else in the file changes.

The binary is patched rather than rebuilt because a rebuild from this tree does not reproduce the shipped file: built with `FEX_IOS_HOST_BUILD=ON`, `TUNE_CPU=generic`, `fmt`
disabled and the repo's own toolchain (clang 22.1.4, the same commit as the shipped file), 3,323 of 14,687 functions come out a different size (FEXCore's X87/string/XSAVE
paths among them), so the shipped file was built from a different FEXCore revision or options. Shipping a rebuild would change how every game runs. Finding the original
recipe is on the public-release list (rebuilt binaries need a recipe).

Apply to a fresh copy of the previous file: `python3 patches/0015-xtajit64-context-guard.py xtajit64.pre-0015.dll vendor/Madeira/app/Madeira/arm64ec-windows/xtajit64.dll`.
The previous file is kept at `…/ec-out/xtajit64.pre-0015.dll` (SHA-256 starts `dc5c980c`). `tools/engine.sh bump` (this changes how a game exits).
