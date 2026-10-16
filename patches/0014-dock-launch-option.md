# 0014: tell the Dock host which launch option to ask Valve's client for

`vendor/Madeira/research/madeira-dock/src/launch.c` (the source of `dockhost.exe`): Valve's client is asked to start a game with `LaunchApp(gameid, launchOption, …)`, and the
host always passed option 0. The options are the numbered entries under the app's `config/launch`; not every app has a 0. Factorio's Windows entries are 1 (64-bit) and 2 (32-bit), so
the client answered `Failed running app 427520 (entry for launch option 0 not found)` in its `content_log.txt` every five seconds, and the host gave up after two minutes with
"Steam did not finish loading this game's configuration" (launch error 22).

The host now reads `MADEIRA_DOCK_LAUNCH_OPTION` (a plain number below 1000; anything else, or unset, means 0 as before). Porthole sets it from the game's launch list
(`SteamLaunchOption.dockDefaultKey`): the lowest-numbered ordinary Windows entry that suits a 64-bit client. Games that start at 0 behave exactly as before. A library list saved by an older build has no numbers, so the number is then "unknown" (not 0) and Porthole fetches that one game's list from Steam just before the launch (`freshLaunchList`); the first 0.50.8 build treated it as 0 and still failed for Factorio.

Rebuild: `build/madeira-dock/build.sh` (the bundled llvm-mingw), then copy `dockhost.exe` and `dock-notices.txt` into the staged `arm64ec-windows` folder. The notices file gains a
"Changes by the Porthole authors" section, as the licence requires for a modified build.
Engine: recorded with `tools/engine.sh accept` (not `bump`): the change only affects games that could not be started this way at all.
