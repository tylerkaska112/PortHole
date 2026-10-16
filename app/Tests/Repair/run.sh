#!/bin/bash
# Compiles DockRegistryRepair for the Mac and checks it against stand-in registry text and a scratch prefix.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
cp "$HERE/main.swift" "$OUT/main.swift"
swiftc -swift-version 5 -o "$OUT/repair" "$OUT/main.swift" "$HERE/../../Runtime/DockRegistryRepair.swift"
"$OUT/repair"
rm -rf "$OUT"
