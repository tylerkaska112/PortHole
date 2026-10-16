# 0023 - guest bytes and stack at a guest trap (diagnostic)

**Problem.** Ubisoft Connect's client (`upc.exe`, 32-bit, anti-tamper sections `.ubx0-.ubx2`) dies about 4 s after it starts: a guest trap right after `popfd; rdtsc` (guest EIP 0x1f05a24), then FEX cannot translate what follows. The log named the register file but not the trapping instruction or the handler.

**Change.** In the `[int3-guest]` block of `build/ntdll-unix/signal_arm64_ios.c`, for a trap in a 32-bit guest (guest RIP below 4 GB, FEX's guest-memory base in x19), print `[trap-bytes]` lines: 32 bytes before RIP and 64 after, and 128 bytes of the guest stack at RSP. First 16 traps only. Read-only; nothing else changes.

**Rebuild.** `tools/rebuild_ntdll_object.sh signal_arm64`, copy the library over `vendor/Madeira/app/Madeira/libntdll_unix.a`, restage (see 0020).

**Engine.** Logging only, recorded with `tools/engine.sh accept`.
