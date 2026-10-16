# 0148 ntdll: crash forensics - the call site and the memory RAX, RCX, R10 point at

`build/ntdll-unix/signal_arm64_ios.c` (`[x86_live]` block of the guest fault report): for the first two faults it now also logs `[x86_code] caller` (48 bytes before the return address on the stack = the instruction that made the bad call), and `rax`, `rcx`, `r10` (the memory they point at). Library `gl-lib-0148` (signal_arm64 object rebuilt on gl-lib-0146).
Reason: Subnautica crashes ~1 s after its world mounts calling 0x36000000_70xxxxxx = a 0x70xxxxxxXX pointer read one byte late (RAX odd, e.g. 0x709b2f0951); cleared: lean call/ret, TSO, hot L1, fast sync, swap, GC_DONT_GC; MONOHACKS=0 stops the game early. The dump should name the instruction and show the slot.
