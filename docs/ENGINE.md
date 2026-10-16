# The game engine version, and what it does to compatibility badges

A compatibility badge says how a game runs. That depends on the **engine** (the emulation layer: the pinned Madeira commit with Wine, FEX and DXMT, our patches to it,
and the glue in `app/Runtime`), not on the app around it. So:

- **Every report records the engine it was made on** (for example `40d5e74-r0`: the Madeira commit plus a revision), and the app version as well.
- **A badge only counts reports from the engine of whoever asks.** An app update that doesn't touch the engine keeps every badge.
- **When the engine changes, badges start empty.** Games show **Not yet tested** until someone plays on the new engine and reports. Older reports are *not* deleted: they stay in the
  game's list, marked "Earlier engine … not counted", on the phone and on the website.
- One install can report once per game, device and engine (an app update on the same engine replaces the report; a new engine adds a new one). After an engine change the app asks again after a play session.
- A game with no verdict is "Not yet tested" in the Library, on the game's page and on the website. The label only appears when the server actually answered, never because the phone was offline.

## What you do when you change things

`app/Config/Engine.xcconfig` records the engine. `tools/engine.sh` keeps it honest:

| You changed | Run |
|---|---|
| the Madeira pin (`vendor/Madeira`), a file in `patches/`, or `app/Runtime` in a way that changes how games run | `tools/engine.sh bump` (a new pin starts at `-r0`; otherwise the revision goes up) |
| the same places, but not behaviour (a comment, a log line) | `tools/engine.sh accept` |
| anything else (screens, Steam, signing, updating, setup) | nothing: it is not the engine |

`tools/release.sh` and `tools/release_public.sh` run `tools/engine.sh check` first and stop if the engine's inputs changed and nobody recorded it. Remember to commit the new `Engine.xcconfig`.
Binaries that are rebuilt outside this repository (`wow64win.dll`, `gdiplus.dll`, the `ec-out` DLLs) are not covered by the check: if you rebuild one in a way that changes behaviour, run `bump` yourself.

## Where it lives

- App: `CompatEngine` (`app/Sources/Compat/CompatCore.swift`) reads `PortholeEngine` from Info.plist; every report, badge, report list and game page request carries it.
- Hub: `hub/compat.js` stores `engine` per report and takes `?engine=` on `/compat/badges`, `/compat/games`, `/compat/games/<id>` and its `/reports`. Without `?engine=` everything counts
  (older apps behave as before). Reports from apps that send no engine count as earlier for anyone who asks by engine. A database from before this is rebuilt on start (nothing is lost).
- Website: `tools/publish_compat_snapshot.py` asks for badges as of the engine in `Engine.xcconfig` and writes `engine`, `countedReports`, `earlierReports` and each report's `onThisEngine` into `compat.json`.

## "Worked in v..." (0.50.41)

The engine mostly adds compatibility, so a past result stays useful. When nobody has reported a game on your engine, the badge is no longer "Not yet tested" if there are earlier reports: it says what the engine reported on most recently before yours said, with the app version that last reported it: **Worked in v0.50.34**, **Somewhat worked in v0.50.34** or **Didn't work in v0.50.34** (outlined, not filled, to show it is a past result). "Not yet tested" now means nobody has reported the game at all. Once someone reports on your engine, that verdict replaces it.

* Hub (`hub/compat.js`, `badge()`): `earlier` gains `verdict`, `engine`, `appVersion`, `date` and `verdictReports` (the verdict of the engine group with the newest report; reports from your phone's model are preferred when there are any). Old apps ignore the new fields and keep showing "Not yet tested".
* App: `CompatPast` (`Compat/CompatBadges.swift`), `CompatPastPill`, used wherever "Not yet tested" appeared for a game with earlier reports.
* **Regressions** (you, not the people using the app): `GET /compat/admin/regressions`, `node hub/compat-admin.js regressions` and the Launcher's Reviews > Regressions list games whose newest engine's verdict is worse than the one before it (works great or playable, then worse). Newer engines mostly add support, so each one is worth a look.

## Debug or Release build

The release scripts (`tools/release.sh`, `tools/release_public.sh`) build the **Release** configuration since 0.50.210. Debug (optimised Swift, `-O`) was the shipped build until
0.50.207 and is still available with `F4_CONFIGURATION=Debug`.

A Release build used to crash the guest. The cause: Xcode links Debug with `-rdynamic` and Release without, and the engine finds Wine's C functions (FreeType, Direct3D, the display
shim, `winios_*`, `jit_*`) in the app's own executable by name. Release dropped about 11,700 of those exports (and hid the app's C glue with `GCC_SYMBOLS_PRIVATE_EXTERN`).
`app/project.yml` now sets `LD_EXPORT_GLOBAL_SYMBOLS` and `GCC_SYMBOLS_PRIVATE_EXTERN = NO` for Release, and `nm -gU` of the two binaries shows the same C exports (36 ObjC class
symbols differ). C code compiles at `-Os` instead of `-O0` in Release.

**Compared on a device (2026-10-10/11, iPhone 15 Pro Max, build 0.50.207 Debug against 0.50.208 Release, the full `docs/TEST-CHECKLIST.md`):** no noticeable difference. Same frame rate
in every game tried (Factorio 60 / 60, Presentable Liberty 30 / 30, Teardown 63 / 63, Supermarket Simulator 44 / 42); Schedule 1 crashes loading a world save on both.
