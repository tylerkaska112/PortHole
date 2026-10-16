# Device test checklist (compare two builds)

Use one copy per run. Install a build, go through the list, write the result in the build's column, then install the other build and repeat.
Always test the SAME device, the SAME games and the SAME network, and restart the device between builds. A cell is `ok`, `FAIL` (say how) or `n/a`.

| | Build A | Build B |
|---|---|---|
| Version (Settings, About) | | |
| Configuration | Debug | Release |
| Device and iOS version | | |
| Signed with (own cert / third party) | | |
| Date | | |

Where a number is asked for, write it down; "felt fine" is hard to compare later. Open the log from Settings (Advanced, Log) after any failure and keep it.

## 1. Install and first start
| Check | A | B |
|---|---|---|
| Installs and opens (no crash on the launch screen) | | |
| Settings, Stores and JIT, Your install: shows what you expect (layout, memory, address space, private link) | | |
| Setup guide: all three steps can be finished | | |
| Home shows the games; a controller moves the selection | | |

## 2. JIT (try each method you use)
| Check | A | B |
|---|---|---|
| Porthole does it: Play switches JIT on, game starts, no second tap | | |
| StikDebug method: opens StikDebug, comes back, game starts | | |
| Other tool: waits, starts when JIT is on | | |
| Private link: comes up and goes down again (Settings, Stores and JIT, Status in Advanced) | | |
| Your own VPN is asked about and comes back (if you use one) | | |

## 3. Games (same list for both builds)
| Game | Starts (s to first frame) | FPS (steady) | Runs 10 minutes | Exit is clean | A | B |
|---|---|---|---|---|---|---|
| Factorio | | | | | | |
| A heavy game that works today: | | | | | | |
| A Steam game through Dock: | | | | | | |
| A game from an installer (Files / .exe): | | | | | | |
| A game that is known not to work (check it still fails the same way): | | | | | | |

Write A and B numbers in the same row as `A / B`, for example `60 / 60` under FPS.

## 4. Steam
| Check | A | B |
|---|---|---|
| Sign in (and a Steam Guard code if asked) | | |
| Library lists your games; Controller tab and badges show | | |
| Download a small game; progress moves; it appears in the library | | |
| Add an installed Steam game back to the library | | |

## 5. Controls
| Check | A | B |
|---|---|---|
| Touch controls work in a game | | |
| Controller: whole app navigable, in-game input works | | |
| Controls editor opens and a change is kept | | |

## 6. Updates and signing
| Check | A | B |
|---|---|---|
| Settings, Updates lists versions, five per page | | |
| Update to a newer build installs and keeps games and settings | | |
| Go back to an older build (downgrade) works | | |
| Sign an update on the device with your certificate | | |

## 7. Lighter installs (only when you test them)
| Check | A | B |
|---|---|---|
| Without the tunnel extension: setup guide does not ask to allow a private link; LocalDevVPN start works | | |
| Without both extensions: JIT through StikDebug works; "Porthole does it" is not offered | | |
| An update keeps the install light (same extensions missing afterwards) | | |

## 8. Reports
| Check | A | B |
|---|---|---|
| After 5 minutes of play the report prompt appears; a report sends | | |
| A crash gives the "closed unexpectedly" prompt | | |

## Notes
Anything that behaved differently between the two columns, with the game, the time and the log lines:

-
