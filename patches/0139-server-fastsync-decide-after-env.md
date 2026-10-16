# 0139 Server: decide on fastsync cells after the variables exist

`wine/server/event.c` (swapped into `libwineserver.a`; `git -C vendor/Madeira/wine apply`).

Evidence (The Forest, 2026-10-14 19:23-19:35, 0.50.325-327): `MADEIRA_FASTSYNC_SEM=1` and `MADEIRA_FS_AUTO_REQS=1` changed the client's startup line (`sem=on`, armed after 121 ms) but not the server load: req29 (select) and req41 (release_semaphore) stayed at ~10,000/s each (22-25k requests/s in all), and every one of 426 `[srv-stuck]` objects, events as well as semaphores, reported `cell=-1`. No object ever had a cell.

Cause: the server latched its decision on the first call of `madeira_fastsync_enabled()`. The app starts the server (`wineserver_start`) before `WineProcessBridge.m` exports `MADEIRA_FASTSYNC` (the default `auto`) and the game's `MADEIRA_FASTSYNC_SEM` for the game process, so the first call - any event creation, or the timeout re-check in thread.c - saw no variable and switched the cells off for the whole session. Fastsync was effectively only the client's peek half.

Fix: while `MADEIRA_FASTSYNC` is not set the answer is "off" but not latched; semaphore cells wait for fastsync's own decision. New lines in the log: `[fastsync] server: cells ON|off (...)` and `[fastsync] server: semaphore cells ON|off (...)`.
Expected: `cell=N` in `[srv-stuck]` lines, req29/req41 far below 10,000/s. Risk: fastsync has so far only run its client half in practice, so the server half and the semaphore path are effectively untested; a hang or `[fastsync] desync` shows it. `env.MADEIRA_FASTSYNC = 0` switches it off per game.
