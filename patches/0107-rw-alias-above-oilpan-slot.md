# 0107 The JIT pool's RW alias starts above Oilpan's slot (opt-in, with 0105/0106)

`app/Runtime/StikJITHelper.swift` (`allocatePool`): with `pa-pool32-soft = 1` in the game's lines, or `MADEIRA_PA_POOL32_SOFT=1`, the RW alias is remapped at `0x7100000000` instead of `0x7000000000`, so the first 4 GB of
that slot can be held for Chromium's Oilpan heap. This was the one change of the 0018 experiment (branch `electron-va-experiment`) that was not in `patches/0018-*.patch`. Applied by `tools/vendor_glue.sh`.
Off by default: `MadeiraConfig.flag(..., fallback: false)`.
