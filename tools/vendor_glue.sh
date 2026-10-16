#!/bin/bash
# Copy the Iridium-free runtime glue from the pinned GitHub Madeira clone (vendor/Madeira, same snapshot the libraries are built from) into app/Runtime.
# Re-runnable; wipes the previously vendored files first. NOT copied: any file mentioning Iridium, FEXBridge/hello_x86 (replaced by app/Sources/Core/RuntimeStubs.c), any UI.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${MADEIRA_ROOT:-$HERE/vendor/Madeira}/app/Madeira"
DST="$HERE/app/Runtime"
FILES="JITAllocator.c JITAllocator.h PrefixExtractor.c PrefixExtractor.h wine_stubs.c IOSDisplayShim.m IOSDisplayShim.h WineProcessBridge.m WineProcessBridge.h WineServerBridge.m WineServerBridge.h
Winios/Winios.h Winios/Winios.m Winios/WiniosCursor.c Winios/WiniosCursor.h Winios/WiniosGamepad.c Winios/WiniosGamepad.h
StikJITHelper.swift EntitlementChecker.swift LogStore.swift LogPattern.swift LogTail.swift MadeiraConfig.swift
SteamKeyValues.swift SteamInstall.swift MadeiraDock.swift SteamRuntime.swift DockInstallers.swift
SteamStorage.swift SteamStorageNative.h DockReset.swift"
# Madeira's own Steam client (SwiftSteam) is NOT taken: Porthole's Steam sign-in, library and downloads are in app/Sources/Steam, written for this project.
# Only the vendored files are replaced: app/Runtime also holds files of our own (DockLaunchOptions.swift, DockRegistryRepair.swift, Bridging-Header.h), which must stay.
for f in $FILES; do rm -f "$DST/$f"; done
for f in $FILES; do
  if grep -qi iridium "$SRC/$f"; then echo "REFUSING $f: mentions Iridium"; exit 1; fi
  mkdir -p "$DST/$(dirname "$f")"; cp -p "$SRC/$f" "$DST/$f"
done
( cd "$DST" && shasum -a 256 $FILES > SHA256SUMS )
# Our own numbered patches to the vendored files (SHA256SUMS above are the pristine upstream hashes). Applied from the repo root.
# 0003 (pool hole) is upstream since #147, so it is no longer applied; 0016 (give back the executable window) is ported to the newer StikJITHelper.
for patch_file in "$HERE"/patches/0011-*.patch "$HERE"/patches/0016-*.patch "$HERE"/patches/0019-*.patch "$HERE"/patches/0083-*.patch "$HERE"/patches/0085-*.patch "$HERE"/patches/0099-*.patch "$HERE"/patches/0100-*.patch "$HERE"/patches/0101-*.patch "$HERE"/patches/0107-*.patch "$HERE"/patches/0150-*.patch; do
  [ -f "$patch_file" ] && ( cd "$HERE" && patch -p1 -s < "$patch_file" ) && echo "applied $(basename "$patch_file")"
done
# Porthole's Telemetry reads LogStore.shared.logFileURL; upstream made it private (the 0.50.233 re-vendor found out).
sed -i '' 's/    private let logFileURL: URL/    let logFileURL: URL/' "$DST/LogStore.swift"
echo "vendored $(echo $FILES | wc -w) files from $SRC @ $(git -C "$HERE/vendor/Madeira" rev-parse --short HEAD)"
