# 0141 (app) Fastsync defaults: semaphores, alertable one-handle waits, 20 ms fast park

`app/Runtime/WineProcessBridge.m`: with fastsync on (MADEIRA_FASTSYNC set and not 0/off/no), `MADEIRA_FASTSYNC_SEM=1`, `MADEIRA_FASTSYNC_ALERTABLE=1` and `MADEIRA_FASTSYNC_CAP_US=20000` are exported with setenv(..., 0): anything from the game's lines or madeira.cfg wins. Cleared again when the session ends.

Evidence, The Forest, same scene, phone cooled or not (no difference): 10-13 fps with fastsync as it shipped (server never made cells: patch 0139), 12-17 fps with SEM + ALERTABLE (0139 + 0140), 23-26 fps with CAP_US=20000. Server requests 23,500/s -> 1,800/s (select 10,000/s -> ~1,200/s, release_semaphore 10,000/s -> ~200/s).

Risk: fastsync's server half and the semaphore/alertable paths had effectively never run before 0139 (the server decided before the variables existed), and now run in every game. A hang or `[fastsync] desync` line in another game: add `env.MADEIRA_FASTSYNC_SEM = 0` / `env.MADEIRA_FASTSYNC_ALERTABLE = 0` (or `env.MADEIRA_FASTSYNC = 0`) to that game's lines and report it. Only on `experimental`; `main` unchanged.
