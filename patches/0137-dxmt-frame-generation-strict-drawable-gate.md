# 0137 Frame generation: count the drawable on the screen, track every frame

`dxmt/src/winemetal/unix/winemetal_unix.c`, applied after 0136.

Log of 2026-10-14 18:43 (0.50.324, iPhone 15 Pro Max, Factorio): the screen really ran at 116-120 Hz (the new `[promote]` line), so the slow frames were not a 60 Hz screen. With the switch on the game fell from 60 to 37-58 fps while the GPU was only 25-40% busy; `extra drawable wait` averaged 9-13 ms (max one 60 Hz refresh) on every generated frame, on the game's own thread.

Cause: the gate of 0135 (`inflight + 2 > maximumDrawableCount`) did not count the frame that is on the screen, which keeps its drawable until the next one replaces it, and the frames that were not generated were not counted at all (never tracked). With a pool of three the second drawable was often not free and `nextDrawable` blocked the game.

* Gate: `inflight + 3 > maxd` (the screen's frame + the game's + the extra one), with a pool of three: only when nothing is waiting to be shown.
* Every frame this path lets through (first frame, skipped, no drawable) is tracked as well.

Expected: no more waits; a 60 fps game on a 120 Hz screen gets a generated frame only now and then (the pair takes the whole frame), a 30 fps game gets one for every frame. Untested on a device.
