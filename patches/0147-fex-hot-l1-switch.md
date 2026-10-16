# 0147 FEX: `env.MADEIRA_FEX_HOTL1 = 0` keeps every thread's lookup cache at 128K entries

`FEXCore/Source/Interface/Core/LookupCache.h`: the growth of a hot thread's L1 lookup cache to 512K entries (0.50.346, patch 0145) can be switched off for a game with `env.MADEIRA_FEX_HOTL1 = 0` (read once; default stays ON). The allocation size is unchanged.
Reason: a bisect. Subnautica (Epic build, Mono) crashes ~1 s after its world finishes mounting with an access violation jumping to a pointer read one byte late (0x3600000070a38a64 and the like); cleared so far: lean call/return (`MADEIRA_FEX_LEAN=0`), TSO (`FEX_TSOENABLED=0`), fast sync, swap, memory; `FEX_MONOHACKS=0` stops the game early (Mono needs the hooks). The hot L1 is the remaining change of mine in that path. Untested.
Build: see 0143 (cmake build of target arm64ecfex, output to ec-out/xtajit64.dll).
