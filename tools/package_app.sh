#!/bin/bash
# Zip the built (unsigned) .app into an IPA, dropping external-drive junk (._* AppleDouble files, .DS_Store) and any stale signature,
# and removing Microsoft's Visual C++ DLLs (the app downloads them instead) and the builder's user name from the source paths the compilers recorded (tools/scrub_paths.py; the .app itself is not touched).
# usage: tools/package_app.sh <path/to/App.app> <out.ipa>
set -eu
app="$1"; out="$2"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
mkdir "$w/Payload"; cp -R "$app" "$w/Payload/"
find "$w" \( -name '._*' -o -name '.DS_Store' \) -delete
rm -rf "$w"/Payload/*.app/_CodeSignature
# Microsoft's Visual C++ DLLs are not ours to put in an IPA: the app downloads them from Microsoft (VCRuntimeInstaller). A private test build can keep
# them with F4_BUNDLE_VCRUNTIME=1.
[ "${F4_BUNDLE_VCRUNTIME:-0}" = 1 ] || find "$w"/Payload/*.app/x86_64-vcruntime -name '*.dll' -delete 2>/dev/null || true
"$(dirname "$0")/scrub_paths.py" "$w/Payload" ${SCRUB_ALLOW:+--allow "$SCRUB_ALLOW"} ${SCRUB_STRICT:+--strict}
case "$out" in /*) dest="$out" ;; *) dest="$PWD/$out" ;; esac
rm -f "$dest"; ( cd "$w" && zip -q -r -X "$dest" Payload )
ls -l "$out"; shasum -a 256 "$out"
