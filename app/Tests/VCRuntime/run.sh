#!/bin/bash
# Compiles VCRuntime.swift for the Mac with its test and runs it. Set VC_REDIST to Microsoft's VC_redist.x64.exe to test the real unpacking.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
swiftc -swift-version 5 -o "$OUT/vcruntime" "$HERE/../../Sources/Core/VCRuntime.swift" "$HERE/main.swift"
"$OUT/vcruntime"
rm -rf "$OUT"
