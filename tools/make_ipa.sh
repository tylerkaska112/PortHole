#!/bin/bash
# Build a test IPA = a base IPA (default: the frozen b79 baseline; override with BASE_IPA=path) + the extra ARM64EC DLLs given on the command line. Nothing else changes.
# usage: tools/make_ipa.sh <label> <dll> [<dll> ...]   -> build/Madeira-0.34.7-b79+<label>.ipa
# The result is UNSIGNED-by-us: the original signature is dropped; re-sign/sideload it the way you install Madeira (Sideloadly/Xcode).
set -eu
cd "$(dirname "$0")/.."
label="$1"; shift
base="${BASE_IPA:-baseline/Madeira-0.34.7-b79.ipa}"
if [ -z "${BASE_IPA:-}" ]; then ( cd baseline && shasum -a 256 -c Madeira-0.34.7-b79.ipa.sha256 >/dev/null ) || { echo "baseline hash mismatch"; exit 1; }; fi
bname=$(basename "$base" .ipa)
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
unzip -q "$base" -d "$w"
app="$w/Payload/Madeira.app"
for f in "$@"; do
  n=$(basename "$f")
  [ -e "$app/arm64ec-windows/$n" ] && { echo "refusing to overwrite existing $n"; exit 1; }
  cp "$f" "$app/arm64ec-windows/$n"
  echo "added arm64ec-windows/$n  sha256 $(shasum -a 256 "$f" | cut -d' ' -f1)"
done
rm -rf "$app/_CodeSignature"
find "$w" \( -name "._*" -o -name ".DS_Store" \) -delete   # AppleDouble junk from external-drive builds
out="build/$bname+$label.ipa"; rm -f "$out"
( cd "$w" && zip -q -r -X "$OLDPWD/$out" Payload )
ls -l "$out"; shasum -a 256 "$out"
