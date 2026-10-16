# Engine options and per-game engine settings

Madeira, the engine under Porthole, has many switches. Porthole offers the ones below without touching any setting it already had. **Nothing here is written, exported or changed until you change that row**; every row starts on *Default*, which leaves the engine as it was, and *Default* removes only that one key from `madeira.cfg`.

## Settings > Engine options (app-wide, in `Documents/madeira.cfg`)

`app/Sources/Core/EngineOptions.swift` lists them (key, text, choices). They are the keys Porthole did not have a screen for: `env.MADEIRA_FAST_SERVER_START` (start games sooner), `pool` (JIT code pool), `totalphys`, `swap-min-mb`, `swap-mode` (broad swap coverage), `eco-qos`, `cpu-count`, the Direct3D 12 keys (`ags-rewrite`, `async-submit`, `fence-chain`, `d3d12-typed-uav-load`, `upload-swap`, `d3d12-core-dll`), `d3d9`, `env.MADEIRA_WG_VIDEO`, `env.MADEIRA_PROMOTE` and the controller keys (`env.MADEIRA_XINPUT`, `env.MADEIRA_PAD_MODE`, `env.MADEIRA_HIDPAD_XINPUT`, `env.MADEIRA_DINPUT_PAD`, `env.MADEIRA_PAD_KBM`).
The settings Porthole already had (swap, swap coverage, video memory, audio buffer, precise math, resolution, power) are **not** in this list and are never written from here. A test checks that.

## A game's Engine page (`Game.engine`, stored in the library file)

AVX and AVX2 (`MADEIRA_FEX_AVX`), frame generation (`MADEIRA_FRAMEGEN`), CPU cores reported (`MADEIRA_CPU_COUNT`), Direct3D 9 anisotropic filtering (`DXMT_D9_ANISO_LIMIT`), reduced-precision x87 (`FEX_X87REDUCEDPRECISION`), a working folder (`MADEIRA_WORKDIR`), the game's own `madeira.cfg` lines (`MadeiraConfig.applyGame`), the controller mode and its binds, and a Home Screen shortcut link. `EngineLaunch.apply(for:)` exports (or unsets, so nothing carries over from another game) these right before a start.

## Controllers (`app/Sources/Core/PadInput.swift`)

Before this, Porthole used controllers for its own menus only; a game never saw one. Now, while a game runs, up to four paired controllers are published to the runtime (`winios_gamepad_set_state`) as Xbox pads. Player 1 can instead be a HID DualSense or generic gamepad (`MADEIRA_HIDPAD`, served by the wineserver), and a game can choose *keyboard and mouse*: the pad types keys and moves the mouse, with the standard layout (WASD on the left stick, mouse on the right, triggers as mouse buttons) and per-game binds. Controllers reach games by default (`env.MADEIRA_XINPUT` off hides them). Not done: Madeira's *touch controller as an Xbox pad* (its own touch layouts feed it; Porthole's on-screen controls send keys).

## Other additions

* **Start games sooner** (`EngineLaunch.waitForWineserver`): waits for the wineserver's own ready signal, at most the old 2 s pause.
* **Overlay and menu**: the performance overlay (off until you turn it on in the in-game menu) can show GPU busy time and the busiest thread, and the engine's swap and memory lines under *Developer details* (the GPU meter is only on while a shown number needs it); the in-game menu's Performance tab has *Power*, *Eco mode* and *GPU sync*, and its Game tab has *Capture the next frame*.
* **Saves** (`SaveBackup.swift`, Settings > Saves): one zip of every Windows user's Documents, Saved Games and AppData (caches and Steam's own files left out), and a restore.
* **Shortcuts**: `porthole://play?exe=<Windows path>` starts a library game (`ShortcutRouter`).
* **Hold the screen at its top refresh rate** (`ProMotionHold`).

## Known gaps

Three existing settings were changed on 2026-10-04, with the maintainer's written approval: *Audio buffer* now sets `MADEIRA_AUDIO_LEAD_MS` (the new Madeira audio's own queue, 10...500 ms, 0 = none) instead of `MADEIRA_AUDIO_CUSHION_MS`, which nothing reads any more; *Swap covers* gained *Broad* (`MADEIRA_SWAP_COVERAGE=broad`, so the separate *Broad swap coverage* engine option was removed; a `swap-mode = 2` line left in madeira.cfg by the old row moves into Swap covers on the next launch (`EngineOptions.migrateSwapMode`); *Video memory* gained 512 MB and 1 GB. Their other choices and defaults are unchanged.

Tests: `app/Tests/Engine/run.sh`.

## Quality of life (0.50.40)

* **Use what works for others** (`Core/RecommendedSettings.swift`, `UI/Game/RecommendedSettingsGroup.swift`): the Hub's summary of how people who rate a game "works great" set it up (power, swap, swap coverage, video memory, precise math, Wine desktop, how it starts), compared with this game now. A setting is suggested only when at least two reports exist and more than half agree on a value that differs from the game's. Applying writes this game's own overrides only and keeps how they were (`Game.settingsUndo`), so it can be undone. Controls, the heat policy and the audio buffer are never suggested.
* **Automatic save backups** (`Core/AutoBackup.swift`, Settings > Saves): after each game, into `Documents/Saves backups/`, newest five kept, skipped when nothing changed (a fingerprint of the files), over 150 MB or under 1 GB free space.
* **Controller rumble**: engine patch `patches/0017-xinput-vibration.md`; app side `Core/PadRumble.swift` (CoreHaptics on the controller's left and right handles), the strength setting `env.PORTHOLE_RUMBLE`.
