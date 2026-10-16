# 0040 - list the Windows calls Black Ops 3 makes (diagnostic, released in 0.50.78)

`wine/dlls/ntdll/signal_arm64ec.c` `trace_emulated_syscall()`: for a process whose image is blackops3.exe, logs `[sc] #n tid ssn ret a1..a4 sp` for each emulated `syscall` (cap 40000). Map ssn to names from the export order of ntdll stubs (`mov eax, ssn`). Rebuilt with `bash vendor/Madeira/build/wine-pe/build-ntdll.sh` (same size/SizeOfImage as shipped). Shipped file backed up at `$F4_BUILD_ROOT/backup-ntdll-before-0040.dll`.
