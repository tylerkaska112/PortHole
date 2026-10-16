# 0135 Frame generation: only when the screen can show two pictures per game frame, without waiting for drawables, and with a two-second report (opt-in, MADEIRA_FRAMEGEN)

`dxmt/src/winemetal/unix/winemetal_unix.c` (the DXMT fork inside the Madeira submodule; apply with `git -C vendor/Madeira/dxmt apply -p1 patches/0135-....patch`).

## Why
Frame generation (MADEIRA_FRAMEGEN) presents a MetalFX-interpolated picture at once and the real frame half a game frame later, so two drawables per game frame. The first version took the second drawable with `[layer nextDrawable]` unconditionally and waited for it.
A CAMetalLayer has two or three drawables; the game's own, the generated one and the real one held back leave none, so the next frame stalled until one reached the screen: the game ran at the screen's pace divided by two, with a full queue's worth of input lag.
Device report: Factorio 60 fps -> about 30 fps, a lot of input lag. If the screen was also not held at its top rate (60 Hz), two pictures per game frame cannot be shown at all.

## What it does
* `MADEIRA_FRAMEGEN_HZ` (set by the app to the screen's maximum rate when frame generation is on; the app now also holds the screen at that rate) tells the engine what the screen can do. A game frame shorter than 1.9 screen periods (the game is faster than half the screen's rate) is presented as it is, with no generating work.
* The frames this path presented are counted until they reach the screen (`addPresentedHandler`); with fewer than two free drawables (`maximumDrawableCount`) a frame is presented as it is instead of waiting.
* `[framegen] <secs> s: game N fps (frame X ms), generated N/s, skipped: screen too slow N, drawables busy N, none N | extra drawable wait avg A max M ms | screen F Hz seen, H asked | in flight now N, most M` every two seconds, and one line at the first generated frame.
* The flow search and the interpolator are not encoded for a skipped frame.

## Not verified / open
On a device only (Factorio). The measured screen rate (`Hz seen`) is the gap between two presented frames, so with generation running it shows the rate of both; the asked rate is what gates. The interpolation itself (block matching on 1/8-size luma, flat depth, no UI mask) is unchanged.

## Rebuild
Compile `winemetal_unix.c` with the flags of `build/dxmt-ios/build.sh` (`compile_objc`), `ar r` the object into a copy of `libdxmt_combined.a` in a `gl-lib-0135` copy of `gl-lib-0119`, then `F4_BUILD_ROOT=/Volumes/MadeiraWork/update2/build-root LIB_OVERRIDES=.../gl-lib-0135 tools/stage_runtime.sh`.
