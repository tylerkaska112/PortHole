# 0100 Dock: "Run them all again" for a game's one-time installs

`app/Runtime/DockInstallers.swift` (`DockInstallScripts.unmark`, `DockInstallers.forget`; applied by `tools/vendor_glue.sh` after 0099) and `app/Sources/UI/Game/GamePage.swift` (a row under One-time installs).

Why: a game's one-time installs are recorded as done in the prefix's registry files (the "has run" values of Steam's install script, here `HKLM\Software\Rockstar Games\Steam\Launcher` and `...\SDK`). After the user deleted Rockstar's launcher files to start again
(2026-10-09: "the full launcher is 100% not installed, a partial install") the start would still count them as done and run nothing. The row removes those values from system.reg / user.reg (a .madeira-bak copy is kept once), puts the choice back on
"Run at next start" and logs `[dock-installers] app=N forgot X recorded value(s) of Y program(s)`. It deletes no files and only works while no session runs. Not verified on a device.
