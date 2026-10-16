# 0047 - a fault in a thread that holds virtual_mutex no longer deadlocks the exception thread (Black Ops 3 hang)

**Problem.** After 0045 Black Ops 3 got past its protection's module lookup, then hung for minutes (no window, ~16% CPU, Steam's own window stays on screen). `[thread-stacks]` in the 10:06 session log: the game's thread sits in `virtual_map_section` -> `_platform_memmove` with 0% CPU (it maps a file as PAGE_EXECUTE_READ, the copy into the view faults), while the Mach exception thread ("wine-x18-exc") waits in `__psynch_mutexwait` inside `ios_virtual_handle_fault_for_thread` - which takes `virtual_mutex`, held by the stopped faulting thread (`server_enter_uninterrupted_section( &virtual_mutex )`). A deadlock.

**Change.** `virtual_ios.c`: the owner (TEB) and recursion depth of `virtual_mutex` are recorded (`ios_vm_note_lock/unlock`; `mutex_lock/unlock` in the file are wrapped; `server_ios.c` calls the notes from `server_enter/leave_uninterrupted_section`). `ios_virtual_handle_fault_for_thread` does not lock when the faulting thread is the owner (it is stopped, nothing can change) and logs `[mach-deliver] 0047 fault at ... in a thread that holds virtual_mutex` (first 12). The fault itself is still handled by the same rules; if it is not serviceable the thread now gets the access violation instead of hanging.

**Rebuild.** `tools/rebuild_ntdll_object.sh virtual server` (the script now knows `server`), copy the library over `vendor/Madeira/app/Madeira/libntdll_unix.a`, restage.

**Open.** WHY the copy faults (destination page protection in mprotect_exec's pool copy?) - the new log line has the address and vprot.
