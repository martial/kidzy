#!/bin/sh
# Build the server, install it as a LaunchAgent for the current user and start it.
set -eu
cd "$(dirname "$0")/.."
make build >/dev/null
LABEL=com.screenclub.kidzy
mkdir -p "$HOME/Library/Kidzy" "$HOME/Library/Logs/Kidzy" "$HOME/Library/LaunchAgents" "$HOME/.config/kidzy"
[ -f "$HOME/.config/kidzy/kidzy.env" ] || cp ops/kidzy.env.example "$HOME/.config/kidzy/kidzy.env"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
cp server/bin/kidzy "$HOME/Library/Kidzy/kidzy"
sed "s|__HOME__|$HOME|g" ops/$LABEL.plist > "$PLIST"
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
sleep 1
curl -fsS http://127.0.0.1:8800/healthz && echo " · kidzy is running (log: ~/Library/Logs/Kidzy/kidzy.log)"
