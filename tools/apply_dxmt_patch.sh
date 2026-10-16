#!/bin/bash
# Apply the DXMT patches (0004 MADEIRA_PRECISE_MATH in DXMT's airconv, 0005, 0080 file-backed buffers) to the pinned DXMT submodule. Idempotent: does nothing if already applied.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"; D="$HERE/vendor/Madeira/dxmt"
for P in 0004-dxmt-precise-math 0005-dxmt-d3d11-3d-copy-fix 0080-dxmt-file-backed-buffers 0088-dxmt-swap-device-context-state; do
if git -C "$D" apply --check -p1 "$HERE/patches/$P.patch" 2>/dev/null; then git -C "$D" apply -p1 "$HERE/patches/$P.patch"; echo "applied $P"; else echo "$P already applied (or does not apply)"; fi
done
