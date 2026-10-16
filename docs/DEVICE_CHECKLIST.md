# Device checklist (0.50.261)

Things that were built and shipped but have **not been seen working on a device**. Do them in order; each says what should happen and which log line proves it
(Settings ▸ Advanced ▸ share the log after a run, or take the game's log from the session). Send the log if anything differs.

| # | Do this | Should happen | Log line |
|---|---|---|---|
| 1 | Start a Steam download of 1 GB or more, press Home, lock the phone, wait 2 minutes, unlock. | The percentage moved while you were away; the speed did not fall to a crawl. | `[bg-download] keep-alive on (steam)`, `left the screen keep-alive=1` |
| 2 | Same, with an Epic download. | It kept going; it did not pause after 30 s. | `[bg-download] keep-alive on (epic)` |
| 3 | While a download runs, lock the phone and look at the lock screen. | A card with the game, percentage, size, speed, time left, Pause and Cancel. Pause pauses; the button becomes Resume; Resume continues; Cancel stops. | `live activity` (a refusal logs `live activity refused`) |
| 4 | Settings ▸ Updates ▸ Versions: tap a version. | A page with its notes (New / Changed / Fixed) and the install button at the bottom. | — |
| 5 | Update the app from that page. With another VPN on, reach the install step. | The popup shows the steps and progress, and the "Pause your VPN?" question inside itself. | `[vpn]`, `[device-install] copied … over 4 connections` |
| 6 | Swipe in from the left edge: on a game's page, a store game's page, Downloads, a Settings page (phone). | It goes back. At the top level of a tab it does nothing. | — |
| 7 | Stores ▸ Epic: sign in, open a game, install a small one. | Grid, game page, Downloads page; Play works afterwards. | `[epic-install]` |
| 8 | An installed Epic game with a newer build on Epic. | "Update" on its tile and page; updating downloads only what changed; Cancel keeps the game installed. | `[epic-install] start … reused=` |
| 9 | Start any Epic game and look at the log. | One read-only line about its cloud saves (status and counts only). This is how the real shape of Epic's answer is learned before saves are ever synced. | `[epic-cloud] probe status=` |
| 10 | Settings ▸ Storage. | Free space, every game with its size, biggest first. Deleting a Steam or Epic game frees its space. Clear temporary files works (not while an update runs). | — |
| 11 | Stores: the sort button in a grid. | A to Z, Recently played, Installed first, Largest first (Steam). The choice is kept. | — |
| 12 | Settings ▸ Stores and JIT ▸ Game storage: choose a folder on an SSD, download a small Steam game, play it, unplug the drive. | Files, progress and caches on the SSD; the game shows as unavailable when unplugged and comes back when plugged in. | `[external-library]` |
| 13 | Scroll a long list with the moving background on. | The background rests while you scroll and moves again after. | — |
| 14 | Setup guide on a phone held sideways, every page. | Buttons in the top row; nothing cut off. | — |

**Not covered here:** the lock-screen card needs the activity extension in the install (Settings ▸ Stores and JIT ▸ Your install says "download card yes").
