# 0012: reuse the registry slots of exited threads

`vendor/Madeira/build/ntdll-unix/signal_arm64_ios.c`: the table that maps a Mach thread to its Windows thread (IOS_MAX_WINE_THREADS = 512) was append-only. A game that starts
and stops many short-lived threads filled it; every later thread then "resolved to the slot-0 TEB (wrong process!)". The Forest makes about 2000 threads in four minutes
(about 65 alive at once), mostly audio-stream timer threads.

Now, only when the table is full, the registration reuses a slot whose thread has exited (the same liveness test as `ios_thread_registry_range_busy`), claiming it with a
compare-and-swap and giving back the extra send rights taken at registration. A run that never fills the table is unchanged. Log line: `[thread-registry] porthole-0012: reused slot …`.

Rebuild (one object into the library, as for patch 0006): compile `signal_arm64_ios.c` with the `compile_one` flags from `build/ntdll-unix/build.sh` as `signal_arm64.o`,
then `xcrun -sdk iphoneos ar r vendor/Madeira/app/Madeira/libntdll_unix.a signal_arm64.o && ranlib`. Run `tools/engine.sh bump` (this changes how games run).
