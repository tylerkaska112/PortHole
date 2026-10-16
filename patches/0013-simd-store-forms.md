# 0013: emulate more SIMD/FP store encodings

`vendor/Madeira/build/ntdll-unix/signal_arm64_ios.c`, the emulator that completes a store to a page the engine keeps read-execute (an executable page the game also writes to).
It knew integer stores and some SIMD stores, but not these, and a store it cannot decode ends the game:

- `str b/h/s/d/q, [xN, xM|wM {, extend}]` (register offset). FEX emits `[xN, wM, uxtw]` for 32-bit (WoW64) games.
- `stur b/h/s/d` (unscaled; Q was already handled).
- `stp`/`stnp` of two S, D or Q registers (signed offset, pre- and post-index; write-back to SP is left alone).

Found from Assetto Corsa (Steam 356400, a 32-bit game), which died at startup with `[store-undecoded] insn=0x3cb84a70` = `str q16, [x19, w24, uxtw]`.
The faulting address comes from the kernel, so each form only needs its size and source register. Rebuild and engine bump: see `0012-thread-registry-reuse.md`.
