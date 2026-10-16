# Testing from a computer (tools/ipad.sh)

`tools/ipad.sh` drives a paired iPad from a Mac so a test cycle does not need someone to send logs back and forth. It uses `xcrun devicectl` and `porthole://` links. **It cannot tap or type**, and the iPad has to be unlocked.

| Command | What it does |
|---|---|
| `status` | the iPad, and the Porthole build installed on it |
| `play 'C:\path\game.exe' [seconds]` | relaunches Porthole (the runtime can not be restarted in-process), starts that library game through `porthole://play`, waits, then copies the log and takes a screenshot |
| `log [folder]` | copies `Documents/madeira-log.txt` and `madeira-log.prev.txt` out of the app's folder |
| `shot [file]` | a screenshot of whatever is on screen |
| `config 'C:\path\game.exe' set key=value` / `unset key` | adds, replaces or removes one line of the game's own config (Game details > This game's config) |
| `update` | installs the newest published build, like Settings > Updates > Update to... |
| `stop` | clears an ended game |
| `session <exe-name> [file]` | copies the newest COMPLETE per-game log (`Documents/logs/<exe>-*.txt`; `madeira-log.txt` is cut at 10 MB) |
| `cycle 'C:\path\game.exe' [seconds]` | one whole test cycle: updates to the newest build made on this Mac (through the app's own Settings > Updates install, waits for the new build number), relaunches, starts the game, waits, copies the game's complete log and a screenshot, then stops Porthole |

The script starts Porthole with the link as the launch argument `-portholeURL <link>` (devicectl's `--payload-url` did not reach the app's link handler, found by testing). That channel only exists for a computer paired with the iPad, so it needs nothing turned on in the app. The same `config`, `update` and `stop` links opened from anywhere else (the Shortcuts app, a web page) still need **Settings > Advanced > Allow remote-control links**, which is off by default because any app or web page could otherwise use them.
Only plain names and numbers are accepted for `config` (letters, digits, `_ . -`, at most 64 characters), and each use is logged as `[remote] ...`.

The log-reading and screenshot commands read the app's own data folder and the screen. Use them on a device you own, with Porthole in front when you take a screenshot.
`IPAD_UDID` and `IPAD_OUT` can be set in `tools/local.env` (not committed); by default the first paired physical iPad is used.
