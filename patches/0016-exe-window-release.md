# 0016: give back the reserved 0x140000000 window when no program of the game needs it

`app/Runtime/StikJITHelper.swift` (the JIT-pool placement) plus Porthole's own `app/Sources/Core/ExecutableWindow.swift` (the decision). The runtime reserves 128 MB at
`0x140000000` for a program that is built to load there with its relocation table stripped (Red Dead Redemption 2). That reservation sits in the middle of the only address band
the translator's code pool may use (`0x119000000` up to the system library cache near `0x180000000`) and splits it: every launch in our logs shows holes of about 440 + 558 + 329 MB,
so the 896 MB pool is cut to 544 to 635 MB (`ml1036: no hole fits a 896MB pool — SHRINKING`). Black Ops 3's 494 MB image did not fit.

Before the pool is placed, Porthole now reads the PE headers of the game's main program and of every other `.exe` in its folder. If none of them needs the window (relocations present,
or a base outside the window), `StikJITHelper.releaseExeWindowReason` is set and the window is released: the hole below it and the hole above it join (about 1.1 GB) and the full pool
fits. Any doubt (unreadable file, a program that cannot be moved, a Windows system program, the switch turned off) keeps the window, which is exactly the previous behaviour.
Log lines: `[exe-window] can be given back|kept: …`, then `0016: gave back the executable window …` or `0016: keeping the executable window …`.

## Going back

* **Settings > Advanced > "Bigger code pool when the game allows it"** off: the window is always kept, as before (default on). No reinstall needed.
* The previous `StikJITHelper.swift` is `patches/0016-exe-window-release.patch` reversed; a copy is at `…/ec-out/StikJITHelper.swift.pre-0016`.
* Engine r3 (0.50.16 / 0.50.17) stays on the Hub; installing it brings the old behaviour back.

Costs to watch: a larger pool lets games keep more translated code and image copies, which counts toward iOS's memory limit (the pool stays "jetsam-counted"); a game that was fine at
~550 MB and is now killed for memory is the sign to turn the switch off. `tools/engine.sh bump` (this changes how games run).
