# 0039 - guest code bytes around the faulting call (diagnostic)

**Problem.** Black Ops 3 (engine r8, patch 0029 on) runs ~15 s in its protected code and then calls a null pointer (`blr x11` with x11 = 0 from FEX's dispatch, guest `rip` = `blackops3.exe+0x212d814`, return address `+0x212d84c`). The log has 16 bytes at `rip`, too few to say which pointer was called or where it came from.

**Change.** `build/ntdll-unix/signal_arm64_ios.c`, in the `[x86_callret]` block: `[x86_code] call-site <addr>: <hex>` (0x1c0 bytes up to and 0x20 after the newest return address) and `[x86_code] rip ...` (0x40 before / 0x80 after `State.RIP`), read with `mach_vm_read_overwrite` (cannot fault). Logging only; disassemble with `llvm-objdump -D -b binary -m i386:x86-64`.

**Rebuild.** `tools/rebuild_ntdll_object.sh signal_arm64`, copy the library over `vendor/Madeira/app/Madeira/libntdll_unix.a`, restage.
