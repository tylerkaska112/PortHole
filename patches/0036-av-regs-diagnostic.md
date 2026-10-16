# 0036 - guest registers and pointed-to text at a fault (diagnostic)

**Problem.** CS2 dies in `embree3.dll+0x1bec` (a helper that measures a C string, rdx, and writes it to a C++ stream, rcx, whose first qword is null) with and without `-nosound`; the log does not say what the message is.

**Change.** `build/ntdll-unix/signal_arm64_ios.c`, next to `[rsp-forensics]` (so the first six faults only): `[av-regs]` (all guest registers) and `[av-mem]` for RDX, RCX, RSI, RDI, R8, R9: the register value, 96 bytes of what it points at as text, and four qwords. Read with `mach_vm_read_overwrite` (cannot fault). Logging only.

**Rebuild.** `tools/rebuild_ntdll_object.sh signal_arm64`, copy the library over `vendor/Madeira/app/Madeira/libntdll_unix.a`, restage.
