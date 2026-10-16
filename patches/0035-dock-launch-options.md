# 0035 - launch options for Steam-library (Dock) games

**Problem.** The "Launch options" row of a game's page (`Game.args`) was only used for programs Porthole runs directly (`MADEIRA_ARGS`); a Dock launch starts Valve's client and the row did nothing. CS2 testing needed `-insecure` / `-nosound`.

**Change.** `app/Runtime/DockLaunchOptions.swift`: before a Dock start (nothing runs, the file is not in use) the row's text is written as `LaunchOptions` into each `Steam/userdata/<account>/config/localconfig.vdf`, Software > Valve > Steam > apps > <appid>, which is where Valve's client keeps a game's launch options and reads them when it launches the game. A text edit: every other line stays, CRLF kept, `"` and `\` escaped; an empty row removes the line. Called from `SessionController.launch(dock:)`. Log: `[dock-launch] launch options for app N: ... written to M account file(s)`. Host test `app/Tests/LaunchOptions/run.sh`; also run on a copy of the device's real file (the existing `"730"` block got the line).

**Unverified.** Whether the headless client really appends the options to the game's command line: check the game's own command line in the next log (`NtCreateUserProcess ... cs2.exe ...`).
