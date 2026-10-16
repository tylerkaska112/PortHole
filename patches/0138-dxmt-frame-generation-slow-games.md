# 0138 Frame generation for games at 10-15 fps

`dxmt/src/winemetal/unix/winemetal_unix.c`, applied after 0137.

Log of 2026-10-14 18:52 (0.50.325, The Forest at 8-16 fps, switched on in the menu): the user saw a difference in smoothness, but only 0-8 frames/s were generated out of ~13: a frame longer than 66 ms was taken for a stall and dropped the history (`d > 1/15`).

* Stall limit 66 ms -> 160 ms.
* Motion search radius 6 -> 10 blocks when the game frame is longer than 50 ms (a slow game moves further between two frames). `MADEIRA_FRAMEGEN_RADIUS` still overrides.
Untested; the GPU time of the flow search grows with the radius squared (the game is CPU-bound, so there is room).
