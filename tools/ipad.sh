#!/bin/bash
# Drive a paired iPad from this Mac: start a game, read its log, take a screenshot, change a game's config line, install the newest update.
# Needs: the iPad paired with this Mac, unlocked, and a Porthole build that reads -portholeURL (0.50.53 and later). No toggle in the app is needed: the link comes as a launch argument.
# It cannot tap or type. Everything goes through `xcrun devicectl` and the porthole:// links (see app/Sources/Core/ShortcutRouter.swift).
#
#   tools/ipad.sh status
#   tools/ipad.sh play 'C:\Games\Foo\foo.exe' [seconds]        relaunch Porthole, start that library game, wait, then copy the log and take a screenshot
#   tools/ipad.sh log [dest-folder]                            copy madeira-log.txt (and the previous run's) from the app's folder
#   tools/ipad.sh shot [dest-file]                             screenshot of whatever is on screen
#   tools/ipad.sh config 'C:\Games\Foo\foo.exe' set key=value  (or:  unset key)
#   tools/ipad.sh update                                       install the newest published build, like Settings > Updates
#   tools/ipad.sh stop                                         clear an ended game (the app still needs relaunching to start another)
#   tools/ipad.sh session <exe-name> [dest-file]               copy the newest COMPLETE per-game log (Documents/logs/<exe>-*.txt; madeira-log.txt is cut at 10 MB)
#   tools/ipad.sh cycle 'C:\Games\Foo\foo.exe' [seconds]      one test cycle (default 170 s): update to the newest published build (waits for it), relaunch, start the game, wait,
#                                                              copy the game's complete log, stop the app. Prints the log path.
# Settings: IPAD_UDID and IPAD_OUT in tools/local.env (not committed). IPAD_UDID defaults to the first paired physical iPad.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$HERE/tools/local.env" ] && . "$HERE/tools/local.env"
BUNDLE="${PORTHOLE_BUNDLE_ID:-site.portholehq.app}"
OUT="${IPAD_OUT:-${TMPDIR:-/tmp}/ipad-out}"; mkdir -p "$OUT"
DEV="${IPAD_UDID:-}"
if [ -z "$DEV" ]; then
  DEV=$(xcrun devicectl list devices 2>/dev/null | awk '/iPad/ && /paired|connected/ && /physical/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')
fi
[ -n "$DEV" ] || { echo "no paired iPad found (set IPAD_UDID in tools/local.env)"; exit 1; }
urlenc() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }
launch() { # launch <url>: relaunch Porthole (the runtime can not be restarted in-process) and hand it a link as the launch argument -portholeURL
  xcrun devicectl device process launch --device "$DEV" --terminate-existing --activate "$BUNDLE" -- -portholeURL "$1" 2>&1 | tail -3
}
fetch_log() {
  local dest="${1:-$OUT}"; mkdir -p "$dest"
  for f in madeira-log.txt madeira-log.prev.txt; do
    xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
      --source "Documents/$f" --destination "$dest/$f" >/dev/null 2>&1 && echo "copied $dest/$f ($(wc -l < "$dest/$f" | tr -d ' ') lines)" || echo "no $f"
  done
}
shot() {
  local dest="${1:-$OUT/screen-$(date +%H%M%S).png}"
  xcrun devicectl device capture screenshot --device "$DEV" --destination "$dest" 2>&1 | tail -1; echo "$dest"
}
installed_build() { xcrun devicectl device info apps --device "$DEV" --bundle-id "$BUNDLE" 2>&1 | awk -v b="$BUNDLE" '$0 ~ b {print $(NF)}' | tail -1; }
published_build() { # the newest build the Hub lists for Porthole (needs HUB_URL in tools/local.env; falls back to the newest dist/ file name)
  ls -t "$HERE"/dist/Porthole-*-unsigned.ipa 2>/dev/null | head -1 | sed -E 's/.*Porthole-[0-9.]+-([0-9]+)-unsigned.ipa/\1/'
}
session_log() { # session_log <exe-name> <dest>: newest Documents/logs/<exe>-*.txt
  local name="$1" dest="${2:-$OUT/session.txt}" newest
  newest=$(xcrun devicectl device info files --device "$DEV" --domain-type appDataContainer --domain-identifier "$BUNDLE" --subdirectory Documents/logs 2>/dev/null \
           | awk -v n="$name" 'tolower($1) ~ tolower(n) {print $1}' | sort | tail -1)
  [ -n "$newest" ] || { echo "no session log for $name"; return 1; }
  xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "Documents/logs/$newest" --destination "$dest" >/dev/null 2>&1 && echo "$dest ($newest, $(wc -l < "$dest" | tr -d ' ') lines)"
}
case "${1:-}" in
  session) [ -n "${2:-}" ] || { echo "usage: $0 session <exe-name> [dest]"; exit 1; }; session_log "$2" "${3:-}" ;;
  cycle) [ -n "${2:-}" ] || { echo "usage: $0 cycle 'C:\\path\\game.exe' [seconds]"; exit 1; }
        want=$(published_build); have=$(installed_build)
        echo "installed build $have, newest built here $want"
        if [ -n "$want" ] && [ "$have" != "$want" ]; then
          launch "porthole://update"; sleep 10
          for i in $(seq 1 60); do have=$(installed_build); [ "$have" = "$want" ] && break; sleep 5; done
          echo "installed build now $have"; [ "$have" = "$want" ] || { echo "the update did not finish; stopping"; exit 1; }
          sleep 5
        fi
        exe="$(basename "${2//\\//}")"
        # peek=1: the Steam window (the desktop with the Wine console) is shown instead of the launch screen, so the screenshot shows what the host prints
        launch "porthole://play?exe=$(urlenc "$2")&peek=1"; sleep "${3:-170}"
        shot "$OUT/cycle-screen.png" >/dev/null
        pid=$(xcrun devicectl device info processes --device "$DEV" 2>/dev/null | awk '/Porthole.app/ {print $1; exit}')
        [ -n "$pid" ] && xcrun devicectl device process terminate --device "$DEV" --pid "$pid" --kill >/dev/null 2>&1; sleep 6
        session_log "$exe" "$OUT/cycle-session.txt" || fetch_log
        f="$OUT/cycle-session.txt"
        echo "--- markers in the log:"; grep -a -n -E "shutdown-begin=1|launch-game-ended=1|NtTerminateProcess\(handle=0xffffffffffffffff, exit_code=0x[0-9a-f]*[1-9a-f]|Unhandled page fault|UNHANDLED|abort_process|x86_live\] RAX" "$f" | cut -c1-170 | head -12
        echo "--- last telemetry:"; grep -a "\[telemetry\]" "$f" | tail -1 | cut -c1-150 ;;
  status) xcrun devicectl list devices 2>&1 | grep -E "Name|$DEV" | cut -c1-160; xcrun devicectl device info apps --device "$DEV" --bundle-id "$BUNDLE" 2>&1 | tail -3 ;;
  play) [ -n "${2:-}" ] || { echo "usage: $0 play 'C:\\path\\game.exe' [seconds]"; exit 1; }
        launch "porthole://play?exe=$(urlenc "$2")&peek=1"; sleep "${3:-25}"; shot; fetch_log ;;
  log) fetch_log "${2:-}" ;;
  shot) shot "${2:-}" ;;
  config) [ $# -ge 4 ] || { echo "usage: $0 config 'C:\\path\\game.exe' set key=value | unset key"; exit 1; }
        case "$3" in set|unset) ;; *) echo "use set or unset"; exit 1 ;; esac
        launch "porthole://config?exe=$(urlenc "$2")&$3=$(urlenc "$4")"; sleep 6; fetch_log | head -1; grep -a "\[remote\]" "$OUT/madeira-log.txt" | tail -3 ;;
  update) launch "porthole://update"; sleep 8; fetch_log | head -1; grep -a "\[remote\]" "$OUT/madeira-log.txt" | tail -3 ;;
  stop) launch "porthole://stop"; sleep 4; fetch_log | head -1; grep -a "\[remote\]" "$OUT/madeira-log.txt" | tail -2 ;;
  *) sed -n 2,16p "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
