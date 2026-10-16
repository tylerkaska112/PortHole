# 0133 0132's stack scan stays inside mapped memory

0.50.316 (0132) made Sekiro end with exit code 0x80000101 instead of its own error: the log shows `bus_handler BUS #1 ... addr=0x7041a40000` (the first byte past the top of the thread's stack, `prot=0`), `[bus-regs] x0=7041a3da20 x1=7041a40000 x2=8a0`
and `Assertion failed: (!jmp || !ntdll_get_thread_data()->jmp_buf), function ntdll_set_exception_jmp_buf, file thread_ios.c, line 2361`: the 4 KB blind read above the exception's stack pointer crossed the stack base, `NtReadVirtualMemory`'s protected copy
faulted inside exception dispatch, and the nested protection tripped the engine's assertion. Fix: read at most up to `NtCurrentTeb()->Tib.StackBase` (and only if the base is plausible); follow stack pointers only into the program image (`SizeOfImage` from its headers) or the stack itself.
Lesson: inside exception dispatch every read must be of memory known to be mapped; `NtReadVirtualMemory` returning a status is not enough in this engine.
