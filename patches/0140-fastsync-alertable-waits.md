# 0140 Fastsync: opt-in fast path for one-handle alertable waits (`MADEIRA_FASTSYNC_ALERTABLE=1`)

`wine/dlls/ntdll/unix/sync.c` (member sync.o of libntdll_unix.a, rebuilt with `tools/rebuild_ntdll_object.sh sync`; `git -C vendor/Madeira/wine apply`).

Evidence (The Forest, 0.50.328, server cells working after 0139): events dropped from ~5,000 to ~1,100 requests per 8 s (req31), but req29 `select` and req41 `release_semaphore` stayed at ~10,000/s each. `[srv-stuck]` shows the Unity worker threads parked on ONE job semaphore (cell=165, max 2147483647) with `alertable=1 nhandles=1 timeout=60 s`: the semaphore has a cell, but fastsync deliberately sends every alertable wait to the server, so each wait is a `select` and each release finds a server-side waiter and goes to the server as well.

Change: with `MADEIRA_FASTSYNC_ALERTABLE=1` (needs fastsync on) NtWaitForSingleObject and a one-handle NtWaitForMultipleObjects take `madeira_fast_wait` also when alertable. A wait that is satisfied at once returns the status and leaves a queued APC for the next alertable wait (what Windows does with a signaled object); one that has to sleep parks at most MADEIRA_FASTSYNC_CAP_US (2 ms), then goes to the server as before, which delivers APCs. So an APC can be delayed by up to 2 ms while the thread is in a fast wait. Startup line: `[fastsync] mode=... alertable=on`.
Multi-handle, wait-all, SignalAndWait, keyed events stay on the server.
Untested. To try: engine lines `env.MADEIRA_FASTSYNC_SEM = 1` and `env.MADEIRA_FASTSYNC_ALERTABLE = 1`; req29/req41 should fall.
