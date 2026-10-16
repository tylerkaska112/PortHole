#!/bin/bash
# Compiles GameDiscovery.swift for the Mac with its test and runs it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
swiftc -swift-version 5 -o "$OUT/discovery" "$HERE/../../Sources/App/GameDiscovery.swift" "$HERE/main.swift"
"$OUT/discovery"
rm -rf "$OUT"
