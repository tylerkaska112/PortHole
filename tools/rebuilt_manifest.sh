#!/bin/bash
# Prints (or, with --check, verifies) the SHA-256 of every binary Porthole ships that is NOT byte-for-byte the pinned Madeira file.
# The list is docs/REBUILT_BINARIES.sha256. After rebuilding one of them on purpose, run `tools/rebuilt_manifest.sh > docs/REBUILT_BINARIES.sha256` and commit it.
# usage: tools/rebuilt_manifest.sh [--check]
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$HERE/tools/local.env" ] && . "$HERE/tools/local.env"
FARM="$HERE/vendor/Madeira/app/Madeira"
I386="${OVERRIDES_I386:-${F4_BUILD_ROOT:-$HERE/build}/ec-out-i386}"
# Files under the pinned snapshot that we changed or added (git says which). The two libraries we patch are ignored by git, so they are named here;
# the 32-bit xinput DLLs live in the build drive's ec-out-i386 and are staged over the 32-bit farm (shown as i386-windows/...).
list() {
  ( cd "$FARM" && { git ls-files -m -o --exclude-standard -- '*.dll' 2>/dev/null; echo libntdll_unix.a; echo libwin32u_unix.a; echo libdxmt_combined.a; } | sort )
  for f in "$I386"/*.dll; do [ -f "$f" ] && echo "i386-windows/$(basename "$f")"; done
}
where() { case "$1" in i386-windows/*) echo "$I386/$(basename "$1")";; *) echo "$FARM/$1";; esac; }
if [ "${1:-}" = "--check" ]; then
  fail=0
  while read -r sum name; do
    path="$(where "$name")"
    if [ ! -f "$path" ]; then
      # The 32-bit DLLs live in the build folder (F4_BUILD_ROOT/ec-out-i386); when that folder is not here (another machine, drive not mounted) they are skipped, not failed.
      case "$name" in i386-windows/*) [ -d "$I386" ] || { echo "SKIPPED $name (no $I386 here)"; continue; };; esac
      echo "MISSING $name"; fail=1; continue
    fi
    [ "$(shasum -a 256 "$path" | cut -d' ' -f1)" = "$sum" ] || { echo "DIFFERENT $name"; fail=1; }
  done < "$HERE/docs/REBUILT_BINARIES.sha256"
  [ $fail = 0 ] && echo "all rebuilt binaries match docs/REBUILT_BINARIES.sha256"; exit $fail
fi
list | while read -r f; do printf "%s  %s\n" "$(shasum -a 256 "$(where "$f")" | cut -d" " -f1)" "$f"; done
