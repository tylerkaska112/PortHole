#!/bin/bash
# Installs (or updates) the hourly job that refreshes the website's compatibility list: copies the two scripts to
# ~/Library/Application Support/Porthole/bin and loads a LaunchAgent that runs them at minute 0 of every hour.
# Remove it with:  launchctl bootout gui/$(id -u)/site.portholehq.compat-snapshot && rm ~/Library/LaunchAgents/site.portholehq.compat-snapshot.plist
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/Library/Application Support/Porthole/bin"
PLIST="$HOME/Library/LaunchAgents/site.portholehq.compat-snapshot.plist"
LOG="$HOME/Library/Logs/Porthole/compat-snapshot.log"
mkdir -p "$BIN" "$(dirname "$PLIST")" "$(dirname "$LOG")"
cp "$HERE/refresh_site_compat.sh" "$HERE/publish_compat_snapshot.py" "$BIN/"
chmod +x "$BIN/refresh_site_compat.sh"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>site.portholehq.compat-snapshot</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$BIN/refresh_site_compat.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PL
launchctl bootout "gui/$(id -u)/site.portholehq.compat-snapshot" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed: runs at minute 0 of every hour; log: $LOG"
