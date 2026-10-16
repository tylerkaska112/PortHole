# 0136 Frame generation can be switched on and off while the game runs (in-game menu)

`dxmt/src/winemetal/unix/winemetal_unix.c`, applied after 0135 (`git -C vendor/Madeira/dxmt apply -p1`).

* `void madeira_framegen_set(int on, double hz)` / `int madeira_framegen_get(void)` (declared in `app/Runtime/Bridging-Header.h`): the Performance tab of the in-game menu calls them. Switching resets the history, logs `[framegen] ON|OFF from the app (screen N Hz)` and sets the layer's `framebufferOnly` (kept from `_MetalLayer_setProps`) so that new drawables can be read; `hz` is the screen's top refresh rate, which the 0135 gate needs.
* A frame whose drawable still has `framebufferOnly` (from before the switch) is presented as it is. The interpolator and history textures are released on the encode thread at the first present after the switch off.
* App side: `GameMenu.swift` (Frame generation toggle in the Engine card), `HUD.swift` (`setFrameGen`), `ProMotionHold.setFrameGeneration` (the 120 Hz hold follows the switch).

Log of 2026-10-14 18:18 (0.50.321, the old code, Factorio): the game ran at 25 fps (frame 27-41 ms) with GPU busy 25-27 ms per frame (65-71%) and `nextDrawable BLOCKED 66-153 ms`: the interpolation costs most of the frame, besides the drawable stall 0135 addresses. The switch makes it possible to compare the same scene with and without it (`[gpu-perf]` lines, the performance overlay).
