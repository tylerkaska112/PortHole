# 0142 NtYieldExecution: `yield-mode` (opt-in alternatives to sched_yield)

`wine/dlls/ntdll/unix/sync.c` (member sync.o; `tools/rebuild_ntdll_object.sh sync`).

Evidence (The Forest, profiles of 2026-10-14 21:04 and 21:16): 37-52 % of all looks of running threads were in `libsystem_kernel swtch_pri <- cthread_yield`, ten threads at 97-99 % of their own looks, while the engine's counter says `yield 845/s (slept 0/s)` and the threads' thread_info cpu_usage is ~0. sched_yield is swtch_pri on iOS: the caller is depressed until the other runnable threads have run, which is milliseconds per call with every core busy; the adaptive sleep of ml1124 (a streak of yields less than 2 ms apart) never triggers because the calls are further apart than that. A thread that waits for work with SwitchToThread is therefore parked for a scheduler round per attempt: work that arrives waits for it.

New engine line `yield-mode = N` (madeira.cfg / the game's lines): 0 = sched_yield as before (default), 1 = thread_switch(NONE) (no depression), 2 = no yield (the caller spins), 3 = sleep 50 us. Startup line `[sync-census] 0141 yield-mode=N` (the patch carries the number 0141 in the code; this note is 0142).
App: the profiler leaves threads inside swtch_pri out of its shares and reports their number.
Untested.
