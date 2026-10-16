#!/bin/bash
# The "engine" is the emulation layer the games run on: the pinned Madeira commit, our patches to it, and the glue in app/Runtime.
# Compatibility badges are tied to it, not to the app version: an app update that leaves the engine alone keeps every badge, and a new engine
# starts with none until people have played on it (older reports stay visible, marked as earlier).
#
#   tools/engine.sh show      what the engine is now, and whether app/Config/Engine.xcconfig matches
#   tools/engine.sh check     exit 1 if the engine changed since Engine.xcconfig was written (release.sh runs this)
#   tools/engine.sh bump      the change DOES affect how games run: raise the revision and record it  (new badges start from zero)
#   tools/engine.sh accept    the change does NOT affect how games run (a comment, a log line): record it without a new engine
#
# After a new Madeira pin, patch or runtime change, run `bump`. Changes elsewhere in the app (screens, Steam, signing, updating) are not the engine.
set -euo pipefail
cd "$(dirname "$0")/.."
CONF=app/Config/Engine.xcconfig

# What the engine is made of: the Madeira commit recorded in git, every patch (the .dll too), and the glue code.
pin() { git ls-tree HEAD vendor/Madeira | awk '{print $3}' | cut -c1-7; }
digest() {
  { git ls-tree HEAD vendor/Madeira | awk '{print $3}'
    find patches -type f ! -name .DS_Store | LC_ALL=C sort | while read -r f; do echo "$f"; shasum -a 256 "$f" | cut -d' ' -f1; done
    find app/Runtime -type f ! -name .DS_Store ! -name PROVENANCE.md | LC_ALL=C sort | while read -r f; do echo "$f"; shasum -a 256 "$f" | cut -d' ' -f1; done
  } | shasum -a 256 | cut -d' ' -f1
}
get() { sed -n -E "s/^$1[[:space:]]*=[[:space:]]*([^[:space:]/]+).*/\1/p" "$CONF" | head -1; }
write() { # madeira revision digest
  cat > "$CONF" <<CONF_EOF
// The game engine this source builds (see tools/engine.sh). Compatibility badges belong to an engine, not to an app version.
// Do not edit by hand: run  tools/engine.sh bump  after a change that affects how games run (a new Madeira pin, a patch, the runtime glue).
PORTHOLE_ENGINE_MADEIRA = $1
PORTHOLE_ENGINE_REVISION = $2
PORTHOLE_ENGINE_ID = $1-r$2
// The inputs this engine was recorded from; tools/engine.sh check compares against them.
PORTHOLE_ENGINE_INPUTS = $3
CONF_EOF
}

recorded_madeira=$(get PORTHOLE_ENGINE_MADEIRA); recorded_rev=$(get PORTHOLE_ENGINE_REVISION); recorded_inputs=$(get PORTHOLE_ENGINE_INPUTS)
now_madeira=$(pin); now_digest=$(digest)
case "${1:-show}" in
  show)
    echo "engine ${recorded_madeira}-r${recorded_rev} (Madeira ${recorded_madeira})"
    [ "$now_digest" = "$recorded_inputs" ] && echo "matches the source" || echo "the source has changed since: run  tools/engine.sh bump  (or accept)"
    ;;
  check)
    if [ "$now_digest" = "$recorded_inputs" ]; then echo "✓ engine ${recorded_madeira}-r${recorded_rev} matches the source"; exit 0; fi
    echo "✗ the game engine changed (Madeira pin, patches/ or app/Runtime) but app/Config/Engine.xcconfig was not updated."
    echo "  It changes how games run → tools/engine.sh bump     (badges for the new engine start from zero)"
    echo "  It does not             → tools/engine.sh accept"
    exit 1
    ;;
  bump)
    if [ "$now_madeira" != "$recorded_madeira" ]; then rev=0; else rev=$((recorded_rev + 1)); fi
    write "$now_madeira" "$rev" "$now_digest"; echo "engine is now ${now_madeira}-r${rev}"
    ;;
  accept)
    write "$now_madeira" "$recorded_rev" "$now_digest"; echo "recorded; the engine stays ${now_madeira}-r${recorded_rev}"
    [ "$now_madeira" = "$recorded_madeira" ] || { echo "(the Madeira pin changed, so this is a new engine: use bump)"; exit 1; }
    ;;
  *) echo "usage: tools/engine.sh show|check|bump|accept"; exit 1 ;;
esac
