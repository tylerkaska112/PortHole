#!/bin/bash
# Generate DXMT's airconv shader headers (air_msad.h, air_samplepos.h, air_tessellation.h) the way DXMT's meson does (metal -> xxd -n NAME -i),
# which build/dxmt-ios/build.sh does not do. Metal toolchain 32023 (Xcode 27) added a 5th "flags" argument to the internal
# __metal_atomic_fetch_add_explicit intrinsic that air_tessellation.metal calls with 4, so that one shader is compiled from a patched COPY (see patches/0002).
set -eu
R="$(cd "$(dirname "$0")/../vendor/Madeira" && pwd)"
SRC="$R/dxmt/src/airconv/shaders"; OUT="$R/build/dxmt-ios/shader-headers"; mkdir -p "$OUT"; cd "$OUT"
for n in air_msad air_samplepos air_tessellation; do
  in="$SRC/$n.metal"
  if [ "$n" = air_tessellation ]; then
    sed 's/__METAL_MEMORY_SCOPE_THREADGROUP__);/__METAL_MEMORY_SCOPE_THREADGROUP__, __METAL_MEMORY_FLAGS_NONE__);/' "$in" > "$OUT/$n.patched.metal"
    in="$OUT/$n.patched.metal"
  fi
  xcrun -sdk macosx metal -o "$n.air" -c "$in" -std=metal3.1 --target=air64-apple-macos14.0
  xxd -n "$n" -i "$n.air" "$n.h"
  echo "$n.h $(wc -c < $n.h) bytes"
done
