#!/bin/bash
# RETIRED: patch 0006 no longer applies. Madeira's own audio pacing (ml1230: a ring-fill lead, MADEIRA_AUDIO_LEAD_MS, default 60 ms) replaced the code it changed and solves the same
# choppy-audio problem, so since the Madeira update of 2026-10-04 Porthole uses upstream's audio unchanged; see patches/0006-RETIRED.md.
# (old description) Apply patches/0006 (audio jitter cushion in Madeira's audio_null_ios.c) to vendor/Madeira, then rebuild just that object into libntdll_unix.a:
#   tools/apply_madeira_patch.sh            (idempotent; the compile line is the one build/ntdll-unix/build.sh uses for compile_one)
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"; M="$HERE/vendor/Madeira"
if git -C "$M" apply --check -p1 "$HERE/patches/0006-madeira-audio-cushion.patch" 2>/dev/null; then git -C "$M" apply -p1 "$HERE/patches/0006-madeira-audio-cushion.patch"; echo "applied 0006"; else echo "0006 already applied (or does not apply)"; fi
echo "Rebuild: see STATUS.md ('0.8.1') for the one-object compile + 'ar r' into app/Madeira/libntdll_unix.a"
