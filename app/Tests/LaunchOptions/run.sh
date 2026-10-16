#!/bin/bash
# Compiles DockLaunchOptions for the Mac and checks the localconfig.vdf edit against stand-in text.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
cp "$HERE/main.swift" "$OUT/main.swift"
swiftc -swift-version 5 -o "$OUT/t" "$OUT/main.swift" "$HERE/../../Runtime/DockLaunchOptions.swift"
"$OUT/t"
rm -rf "$OUT"
