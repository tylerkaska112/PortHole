#!/bin/bash
# Refreshes the website's compatibility list from the Hub and publishes it when something changed. Run every hour, on the hour, by a LaunchAgent
# (site.portholehq.compat-snapshot) installed with tools/install_site_refresh.sh. It works in its own clone of the website repository, so it never
# touches the working copy, and it lives outside ~/Desktop because launchd jobs are not allowed to read that folder.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
export GIT_AUTHOR_NAME="Porthole" GIT_AUTHOR_EMAIL="noreply@portholehq.site" GIT_COMMITTER_NAME="Porthole" GIT_COMMITTER_EMAIL="noreply@portholehq.site"
HERE="$(cd "$(dirname "$0")" && pwd)"
SITE_DIR="$HOME/Library/Application Support/Porthole/site-clone"
REMOTE="https://github.com/tylerkaska112/porthole-site.git"
echo "▸ $(date '+%Y-%m-%d %H:%M:%S') compatibility snapshot"
if [ ! -d "$SITE_DIR/.git" ]; then
  mkdir -p "$(dirname "$SITE_DIR")"
  git clone -q "$REMOTE" "$SITE_DIR"
fi
git -C "$SITE_DIR" fetch -q origin main
git -C "$SITE_DIR" checkout -q main
git -C "$SITE_DIR" reset -q --hard origin/main
/usr/bin/python3 "$HERE/publish_compat_snapshot.py" --site "$SITE_DIR" --push
