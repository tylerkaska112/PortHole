# 0043 - what the pointers on the guest stack point at (diagnostic)

Follows 0042. The BO3 stack at the failed call shows NtCreateSection's arguments (7 args, file handle 0x64 = R15, PAGE_EXECUTE_READ, SEC_COMMIT-like flags) and the game's wide path buffers ("C:\windows\system32\ntdll.dll", "...common\Call of Duty Black Ops III..."), but not the name that was looked up. `signal_arm64_ios.c`: after the stack dump, `[x86_ptr] slot=<addr> -> <ptr>: <64 bytes hex>` for the first 200 distinct non-stack pointers in the dumped range. Logging only.
