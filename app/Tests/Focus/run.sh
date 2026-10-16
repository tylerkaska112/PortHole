#!/bin/bash
# Compiles FocusSpatial.swift (CoreGraphics only) with its checks and runs them.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
swiftc -o "$OUT/t" ../../Sources/UI/Kit/FocusSpatial.swift main.swift 2>&1 | grep -v "^$" || true
"$OUT/t"
