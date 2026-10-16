# 0017: controller rumble (XInput vibration reaches the controller)

The engine read the controller's buttons and sticks through one custom syscall (`NtUserCallTwoParam_GetGamepadState`, ops *State* and *Caps*) but had no way back: `XInputSetState` returned success and did nothing, and the capability block said the pad had no force feedback ("Controller rumble is not implemented by this transport").

* `wine/include/ntuser.h`: a new op, `NtUserGamepadOp_Vibration` (a 4-byte `XINPUT_VIBRATION`, in). Appended, so existing op numbers do not change.
* `wine/dlls/xinput1_3/main.c` (shared by xinput1_1, 1_2, 1_3, 1_4; xinput9_1_0 forwards to 1_4): `XInputSetState` passes the motor speeds to the new op when the host pad answers.
* `build/win32u-unix/driver_ios.c` (`ios_gamepad_query`): op 2 calls `winios_gamepad_set_vibration(index, left, right)`, defined by the app (`app/Sources/Core/PadRumble.swift`, which plays it on the controller's haptic engines); the capability block now says force feedback is supported (`XINPUT_CAPS_FFB_SUPPORTED`, motors 255).
* 32-bit programs need no change in `wow64win`: it already translates the buffer pointer of this syscall and the payload has the same layout in 32 and 64 bits.

## Rebuild

1. `bash build/win32u-unix/build.sh` (libwin32u_unix.a). The script merges FreeType into the archive again on every run, so afterwards write the archive without duplicate members: extract it, `ar rcs` the unique names, `ranlib` (89 members; 131 or 173 means duplicates).
2. `bash build/wine-pe/build-modules.sh xinput1_1 xinput1_2 xinput1_3 xinput1_4` (arm64ec farm) and `SKIP_DXMT=1 bash build/wine-i386/build.sh xinput1_1 xinput1_2 xinput1_3 xinput1_4` (32-bit farm).
3. Keep the results in `$F4_BUILD_ROOT/ec-out/` (arm64ec) and `$F4_BUILD_ROOT/ec-out-i386/` (i386): `tools/stage_runtime.sh` copies both over the farms, so a re-stage reproduces them.

Engine record: `tools/engine.sh accept` (the badges stay): it only changes what happens when a game asks for vibration, and what the capability block says about force feedback.

## Going back

* Settings > Engine options > Controller rumble: Off ignores every vibration request (the DLLs still call the app, which does nothing).
* The previous 32-bit DLLs are in `/Volumes/MadeiraWork/pre-0017/`; the previous 64-bit ones are in git (`git show <tag>:app/Madeira/arm64ec-windows/xinput1_3.dll` of Madeira at bbbf8d0).

Not covered: a HID DualSense / generic pad (`env.MADEIRA_PAD_MODE`), whose output reports the wineserver ignores, and rumble through DirectInput force feedback.
